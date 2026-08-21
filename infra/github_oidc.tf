# --- quem a AWS aceita como emissor de identidade ----------------------------
# Recurso de CONTA, nao de projeto: existe um unico provider do GitHub por conta
# AWS. Se um dia outro repo seu precisar, ele reusa este - nao cria outro.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# --- em que condicoes essa identidade vira credencial na sua conta -----------


data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }


    # aud = para quem o token foi emitido.

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }


    # sub = quem e o portador. ESTA e a linha que segura a porta: sem ela,
    # QUALQUER repositorio do GitHub, de qualquer pessoa, assume esta role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/main", # deploy
        "repo:${var.github_repository}:pull_request",        # plan no PR
      ]
    }
  }
}


resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_actions" {

  statement {
    sid       = "TerraformState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/*"]
  }

  statement {
    sid       = "TerraformStateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }

  # 2. login no registry: unica acao de ECR que nao aceita recurso especifico
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # 3. push da imagem, restrito AO SEU repositorio
  statement {
    sid       = "EcrRepository"
    actions   = ["ecr:*"]
    resources = [aws_ecr_repository.api.arn]
  }

  # 4. os servicos que a stack gerencia. Em "*" porque boa parte dessas APIs
  # nao suporta permissao por recurso - e porque o terraform tambem precisa
  # LER recursos que ainda nao existem (nao da para nomear o ARN de algo
  # que sera criado no proprio apply).
  statement {
    sid = "ApplicationStack"

    actions = [
      "lambda:*",
      "apigateway:*",
      "logs:*",
      "ssm:*",
      "kms:DescribeKey",
    ]

    resources = ["*"]
  }


  # 5. IAM so dentro do prefixo do projeto: a stack cria a role da Lambda.
  # Sem o prefixo aqui, a CI poderia criar uma role admin para si mesma.
  statement {
    sid = "ProjectRoles"

    actions = [
      "iam:GetRole",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:PassRole",
      "iam:GetRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
    ]
  }

  # 6. o terraform le o proprio provider OIDC a cada plan
  statement {
    sid       = "ReadOidcProvider"
    actions   = ["iam:GetOpenIDConnectProvider"]
    resources = [aws_iam_openid_connect_provider.github.arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.name_prefix}-deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}