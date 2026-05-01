FROM cgr.dev/chainguard/python:latest-dev AS builder

WORKDIR /app

ENV VIRTUAL_ENV=/app/.venv
ENV PATH=/app/.venv/bin:${PATH}

RUN python -m venv /app/.venv

COPY services/analysis/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY services/analysis/main.py /app/main.py

FROM cgr.dev/chainguard/python:latest

WORKDIR /app

ENV VIRTUAL_ENV=/app/.venv
ENV PATH=/app/.venv/bin:${PATH}

COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/main.py /app/main.py

USER nonroot:nonroot
ENTRYPOINT ["python", "main.py"]
