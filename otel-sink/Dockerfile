# Local OTLP/HTTP sink: accepts the member portal's browser trace exports (POST /v1/traces) and discards them.
# Stdlib only (no installs). Nothing is stored or forwarded; no network egress.
FROM python:3.12-alpine
WORKDIR /app
COPY sink.py .
EXPOSE 4318
CMD ["python", "-u", "sink.py"]
