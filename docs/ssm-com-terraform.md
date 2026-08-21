# SSM Parameter Store com Terraform + Lambda

Receita para expor configuração e segredos a uma Lambda sem colocar valores
no código, no state ou em variável de ambiente. Replicável em qualquer projeto:
troque `project_name` / `environment` e o resto funciona igual.

---

## O modelo mental

O erro que custa caro é tratar configuração e segredo como a mesma coisa. São
dois fluxos opostos, e a escolha entre eles decide todo o resto:

|                    | Configuração                 | Segredo                          |
| ------------------ | ---------------------------- | -------------------------------- |
| Exemplo            | `client_url`, `max_retries`  | senha de banco, API key, token    |
| Tipo no SSM        | `String`                     | `SecureString` (criptografa KMS)  |
| Quem é dono do valor | Terraform                  | **ninguém no código** — só a AWS   |
| Onde o valor mora  | `variables.tf`, versionado   | só no Parameter Store             |
| Como muda          | edita o código → `apply`     | `aws ssm put-parameter`           |
| `ignore_changes`   | não                          | **sim**                           |

Na configuração você *quer* que o Terraform imponha o valor do código.
No segredo você quer exatamente o contrário: o Terraform cria a casca vazia
e nunca mais toca no conteúdo.

Ambos são lidos pela aplicação pela mesma API, então o código não distingue os dois.

---

## Passo 1 — `locals.tf`: um prefixo para tudo

```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # todo parametro da aplicacao vive sob este caminho no SSM
  ssm_prefix = "/${var.project_name}/${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

Nome de parâmetro no SSM é hierárquico, como caminho de arquivo. Isso não é
estética — é o que permite:

- ler tudo de uma vez com `GetParametersByPath`, uma chamada só;
- escrever **IAM por prefixo**, de forma que a role de `prod` nunca enxergue
  `/projeto/dev/*`.

Adote `/<projeto>/<ambiente>/<chave>` e não invente outro formato.

---

## Passo 2 — `variables.tf`: duas listas, não uma

```hcl
# Configuracao nao-sensivel: o Terraform e dono do valor.
# Mudou aqui -> apply -> mudou no SSM.
variable "app_config" {
  description = "Non-sensitive parameters exposed to the application via SSM"
  type        = map(string)

  default = {
    client_url = "https://app.exemplo.com"
  }
}

# Segredos: o Terraform cria apenas a casca do parametro.
# O valor e definido fora, via CLI, e nunca aparece no codigo.
variable "app_secrets" {
  description = "Names of sensitive parameters (values defined via CLI)"
  type        = set(string)
  default     = []
}
```

Repare nos tipos, que carregam a diferença:

- `map(string)` — **nome → valor**, porque o Terraform conhece o valor.
- `set(string)` — **só nomes**, porque o Terraform não deve conhecer o valor.

O tipo do HCL já impede o erro: não existe onde escrever a senha em `app_secrets`.

---

## Passo 3 — `ssm.tf`: os dois recursos

```hcl
# --- configuracao: o Terraform e dono do valor -------------------------------
# Para adicionar uma variavel nova, basta uma linha em var.app_config.
resource "aws_ssm_parameter" "config" {
  for_each = var.app_config

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value
}

# --- segredos: o Terraform cria a casca, o valor vem de fora -----------------
# Nasce com placeholder; voce define o valor real com:
#   aws ssm put-parameter --name <nome> --value <valor> --type SecureString --overwrite
resource "aws_ssm_parameter" "secret" {
  for_each = var.app_secrets

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "SecureString"
  value = "PLACEHOLDER-DEFINIR-VIA-CLI"

  # sem isto, o proximo apply reverteria o valor rotacionado para o placeholder
  lifecycle {
    ignore_changes = [value]
  }
}
```

`for_each` sobre um `map` dá `each.key` e `each.value`. Sobre um `set`, dá os
dois iguais ao elemento — por isso o recurso de segredo só usa `each.key`.

O `lifecycle { ignore_changes = [value] }` é a linha central do arquivo. Sem
ela, você rotaciona a senha pela CLI e o próximo `apply` de qualquer pessoa a
reverte para `PLACEHOLDER`, em silêncio, em produção.

---

## Passo 4 — `iam.tf`: as duas permissões

```hcl
data "aws_caller_identity" "current" {}

# ARN da chave KMS padrao do SSM; policy IAM exige ARN de chave, nao de alias
data "aws_kms_key" "ssm" {
  key_id = "alias/aws/ssm"
}

data "aws_iam_policy_document" "lambda_ssm" {
  statement {
    sid    = "ReadAppParameters"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]

    # wildcard no prefixo: parametro novo ja nasce legivel, sem mexer no IAM
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*",
    ]
  }

  # SecureString exige ler (SSM) e descriptografar (KMS) - duas permissoes
  statement {
    sid       = "DecryptWithSsmDefaultKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_key.ssm.arn]
  }
}

resource "aws_iam_role_policy" "lambda_ssm" {
  name   = "${local.name_prefix}-ssm-read"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_ssm.json
}
```

Três detalhes que fazem perder tempo se você não souber:

**Por que duas statements.** `SecureString` envolve dois serviços: o SSM devolve
o valor cifrado, o KMS descriptografa. Só com `ssm:GetParameter` o erro é
`AccessDeniedException` **citando KMS** — e você jura que deu a permissão de SSM,
porque deu mesmo. Faltava a outra.

**Por que `data "aws_kms_key"` em vez do ARN escrito.** Política IAM de KMS exige
o ARN da *chave*; ARN de alias não é aceito no campo `Resource`. O data source
resolve `alias/aws/ssm` para o ARN real, que muda de conta para conta — o que
também mantém o código portável entre projetos.

**Como o ARN se monta.** Nome de parâmetro já começa com `/`, e o ARN é
`...:parameter` + o nome. Então `parameter${local.ssm_prefix}/*` gera
`...:parameter/projeto/prod/*`. Não coloque uma barra a mais.

O wildcard no fim é intencional: parâmetro novo dentro do prefixo já nasce
legível, sem alterar IAM.

> `aws_iam_role_policy` (inline) e não `aws_iam_policy` + attachment: a policy
> inline vive e morre com a role, sem deixar órfão depois de um `destroy`.
> Policy gerenciada só compensa quando várias roles compartilham as permissões.

---

## Passo 5 — `lambda.tf`: passar o caminho, nunca o valor

```hcl
resource "aws_lambda_function" "api" {
  # ... resto da configuracao ...

  # apenas o CAMINHO no SSM, nunca os valores: variavel de ambiente da Lambda
  # aparece em texto puro no console e em GetFunctionConfiguration
  environment {
    variables = {
      SSM_PREFIX = local.ssm_prefix

      # muda sempre que app_config muda. Como alterar a config da funcao
      # descarta os containers vivos, o valor novo passa a valer no apply -
      # sem isto, a Lambda so releria o SSM no proximo cold start espontaneo.
      CONFIG_VERSION = substr(sha1(jsonencode(var.app_config)), 0, 8)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_iam_role_policy.lambda_ssm,
  ]
}
```

**`SSM_PREFIX` guarda o caminho, não os valores.** Variável de ambiente de Lambda
aparece em texto puro no console e em qualquer `GetFunctionConfiguration`. Colocar
segredo ali anula o motivo inteiro de existir o Parameter Store.

**`CONFIG_VERSION` resolve um problema real.** O container da Lambda sobrevive
entre invocações e a aplicação cacheia os parâmetros. Sem esse truque, você muda
`app_config`, roda `apply`, o SSM atualiza — e a função continua servindo o valor
antigo até um cold start espontâneo, que pode demorar horas. O hash muda junto com
a config; mudar a configuração da função faz a AWS descartar os containers vivos;
o valor novo vale já no `apply`.

**`depends_on` na policy.** A função referencia a *role*, então o Terraform sabe
criar a role antes. Mas ela não referencia a *policy* — sem o `depends_on` os dois
podem ser criados em paralelo e a primeira invocação falha por falta de permissão.
Regra geral: `depends_on` existe para dependência real que não aparece como referência.

---

## Passo 6 — lendo na aplicação (Python)

O que fecha o ciclo. O ponto do desenho é ter **um caminho só**, que se comporta
diferente conforme o ambiente:

```python
import os
import pathlib
from functools import lru_cache

import boto3
from pydantic_settings import BaseSettings, SettingsConfigDict

ENV_FILE = pathlib.Path(__file__).parents[2] / ".env"


class Settings(BaseSettings):
    """Precedencia (maior primeiro):
      1. parametros do SSM  - so quando SSM_PREFIX esta definido (Lambda)
      2. variaveis de ambiente
      3. arquivo .env       - desenvolvimento local
      4. defaults abaixo
    """

    model_config = SettingsConfigDict(
        env_file=ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    client_url: str = "http://localhost:5173"


def load_ssm_parameters() -> dict[str, str]:
    prefix = os.environ.get("SSM_PREFIX")
    if not prefix:
        return {}                      # local: cai no .env

    paginator = boto3.client("ssm").get_paginator("get_parameters_by_path")

    params: dict[str, str] = {}
    for page in paginator.paginate(Path=prefix, Recursive=True, WithDecryption=True):
        for parameter in page["Parameters"]:
            params[parameter["Name"].removeprefix(f"{prefix}/")] = parameter["Value"]

    return params


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings(**load_ssm_parameters())
```

**Desenvolvimento local funciona sem AWS.** Local não tem `SSM_PREFIX`, então
`load_ssm_parameters()` devolve vazio e o pydantic-settings cai no `.env`. Sem
mock, sem credencial, sem `if IS_LAMBDA` espalhado pelo código.

**`WithDecryption=True` serve aos dois tipos.** Em `String` é ignorado; em
`SecureString` descriptografa. Por isso a aplicação não precisa saber qual é qual.

**`removeprefix`** transforma `/projeto/prod/client_url` no campo `client_url`.
É o que faz o nome no SSM casar com o nome em `Settings`.

**Kwargs do `Settings(...)` têm prioridade máxima** no pydantic-settings — acima de
variável de ambiente. Ou seja: na Lambda o SSM vence; local não há SSM e o `.env` vence.

`boto3` já vem no runtime da Lambda — declare como dependência **de dev** apenas,
para não embarcar ~15 MB na imagem nem arriscar conflito de versão.

---

## Receitas do dia a dia

### Adicionar uma configuração nova

```hcl
# variables.tf
default = {
  client_url  = "https://app.exemplo.com"
  max_retries = "3"
}
```

Some um campo em `Settings` (`max_retries: int = 3`) e rode `apply`. O IAM tem
wildcard no prefixo, então não precisa tocar nele.

### Adicionar um segredo novo

```hcl
# variables.tf
variable "app_secrets" {
  default = ["database_password"]
}
```

```bash
terraform apply -var="image_tag=..."       # cria a casca com placeholder

aws ssm put-parameter \
  --name "/projeto/prod/database_password" \
  --value 'a-senha-real' \
  --type SecureString \
  --overwrite
```

Some `database_password: str | None = None` em `Settings`. O valor real nunca
passou pelo código nem pelo state.

### Rotacionar um segredo

```bash
aws ssm put-parameter --name "/projeto/prod/database_password" \
  --value "$(openssl rand -hex 32)" --type SecureString --overwrite

# confirme que o Terraform nao quer reverter: tem que dizer "No changes"
terraform plan -var="image_tag=..."

# force os containers a reler (CONFIG_VERSION nao muda para segredos)
aws lambda update-function-configuration \
  --function-name projeto-prod-api \
  --description "rotacao $(date +%s)"
```

O `terraform plan` dizendo **No changes** é a prova de que o `ignore_changes`
está funcionando. Vale rodar sempre depois de rotacionar.

### Conferir o que está lá

```bash
aws ssm get-parameters-by-path --path "/projeto/prod" \
  --recursive --with-decryption \
  --query 'Parameters[].{nome:Name,tipo:Type,valor:Value}' --output table
```

---

## Armadilhas

| Sintoma | Causa |
| --- | --- |
| `AccessDeniedException` citando KMS | falta a statement `kms:Decrypt` |
| IAM não bate mesmo com ARN certo | usou ARN de *alias* KMS; precisa ser ARN de chave |
| IAM não bate, ARN parece certo | barra duplicada: use `parameter${local.ssm_prefix}/*` |
| Valor rotacionado volta ao placeholder | faltou `ignore_changes = [value]` |
| Mudou o SSM e a Lambda serve o valor antigo | container quente com cache; recicle a função |
| Primeira invocação falha por permissão | faltou `depends_on` na inline policy |
| Segredo aparece no `terraform.tfstate` | **é esperado — veja abaixo** |

### O `ignore_changes` não impede o valor de entrar no state

Ele impede o Terraform de **reverter** o valor. Não impede de **lê-lo**: em todo
refresh o provider chama `GetParameter` com descriptografia e grava o valor atual
em `terraform.tfstate`, em texto puro.

Isso não é bug desse recurso. **Tudo que o Terraform gerencia acaba no state.**
A conclusão prática é que o arquivo de state *é ele próprio um segredo*:

- `*.tfstate` no `.gitignore`, sempre;
- backend S3 com criptografia e bloqueio de acesso público;
- acesso ao bucket restrito como você restringiria o segredo em si.

No `plan`, todo `aws_ssm_parameter` aparece como `value = (sensitive value)`,
inclusive os `String`. Isso protege o log da CI, não o state.

Se você quiser que o valor **nunca** encoste no Terraform, a alternativa é não
gerenciar o parâmetro nele: cria uma vez pela CLI e o Terraform só concede o IAM
sobre o path. Perde reprodutibilidade e ganha uma propriedade boa — o segredo
sobrevive a um `terraform destroy`.

---

## Custo

Parameter Store **Standard** é gratuito: até 10.000 parâmetros, 4 KB cada, e a
chave KMS `alias/aws/ssm` não é cobrada. O tier Advanced (8 KB, mais parâmetros)
é pago por parâmetro/mês — você não precisa dele para configuração de aplicação.

Cuidado só com o volume de chamadas: `GetParametersByPath` tem limite de throughput
por conta. Ler uma vez por container e cachear, como acima, mantém o volume trivial.

---

## Checklist para replicar em outro projeto

1. `locals.tf` — definir `ssm_prefix = "/${var.project_name}/${var.environment}"`
2. `variables.tf` — `app_config` (`map(string)`) e `app_secrets` (`set(string)`)
3. `ssm.tf` — os dois recursos; `ignore_changes` **só** no de segredo
4. `iam.tf` — statement de SSM com wildcard no prefixo + statement de `kms:Decrypt`
5. `lambda.tf` — `SSM_PREFIX`, `CONFIG_VERSION` e `depends_on` na policy
6. aplicação — loader que devolve `{}` quando não há `SSM_PREFIX`
7. `.env.example` versionado, `.env` no `.gitignore`
8. definir os valores dos segredos via `aws ssm put-parameter`
9. `terraform plan` → **No changes** (confirma o `ignore_changes`)
