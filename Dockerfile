# ---------- build: resolve as dependencias a partir do uv.lock ----------
FROM public.ecr.aws/lambda/python:3.12 AS builder

COPY --from=ghcr.io/astral-sh/uv:0.12.2 /uv /bin/uv

WORKDIR /build
COPY pyproject.toml uv.lock ./

# --frozen: usa o lock como esta, sem re-resolver (build reproduzivel)
# --no-emit-project: exporta so as dependencias, nao o proprio pacote
RUN uv export --frozen --no-dev --no-emit-project --format requirements.txt -o requirements.txt \
    && uv pip install --target /deps --no-cache -r requirements.txt

# ---------- runtime ----------
FROM public.ecr.aws/lambda/python:3.12

# LAMBDA_TASK_ROOT (/var/task) ja esta no sys.path da imagem base
COPY --from=builder /deps ${LAMBDA_TASK_ROOT}
COPY src/nyc_taxi_regression ${LAMBDA_TASK_ROOT}/nyc_taxi_regression
COPY nyc_city_taxi.pkl ${LAMBDA_TASK_ROOT}/nyc_city_taxi.pkl

ENV MODEL_PATH=${LAMBDA_TASK_ROOT}/nyc_city_taxi.pkl

# pre-compila os .pyc no build: sem isso todo cold start recompila o
# pandas/sklearn do zero (medido: init 2.2s -> 0.7s, 1a invocacao 5.3s -> 1.9s)
RUN python -m compileall -q ${LAMBDA_TASK_ROOT} > /dev/null 2>&1 || true

CMD ["nyc_taxi_regression.lambda_handler.handler"]
