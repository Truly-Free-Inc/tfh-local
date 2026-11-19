# tfh-local: vector-search-trulyfreehome (FastAPI POC). Deps only; the repo is bind-mounted at /app.
FROM python:3.12-slim
RUN pip install --no-cache-dir numpy fastapi uvicorn requests
EXPOSE 8077
