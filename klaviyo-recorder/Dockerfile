# Fake Klaviyo: records every request to a JSONL file and returns 2xx. Stdlib only (no installs).
FROM python:3.12-alpine
WORKDIR /app
COPY recorder.py .
EXPOSE 8090
CMD ["python", "-u", "recorder.py"]
