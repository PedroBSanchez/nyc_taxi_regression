import os
import pathlib
from functools import lru_cache

import boto3
from pydantic_settings import BaseSettings, SettingsConfigDict

# o .env vive na raiz do repositorio, nao dentro do pacote
ENV_FILE = pathlib.Path(__file__).parents[2] / ".env"


class Settings(BaseSettings):
    """Configuracao da aplicacao.

    Precedencia (maior primeiro):
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
    """Le todos os parametros sob SSM_PREFIX e devolve com o prefixo removido.

    Sem SSM_PREFIX (rodando local) devolve vazio, e a Settings cai no .env.
    """
    prefix = os.environ.get("SSM_PREFIX")
    if not prefix:
        return {}

    paginator = boto3.client("ssm").get_paginator("get_parameters_by_path")

    params: dict[str, str] = {}
    for page in paginator.paginate(Path=prefix, Recursive=True, WithDecryption=True):
        for parameter in page["Parameters"]:
            params[parameter["Name"].removeprefix(f"{prefix}/")] = parameter["Value"]

    return params


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings(**load_ssm_parameters())
