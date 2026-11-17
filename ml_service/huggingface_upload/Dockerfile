FROM python:3.11-slim
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 libgomp1 libxcb1 libxext6 libxrender1 libsm6 && rm -rf /var/lib/apt/lists/*
RUN pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
RUN useradd -m -u 1000 appuser
WORKDIR /home/appuser/app
RUN chown appuser:appuser /home/appuser/app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY --chown=appuser:appuser app.py farmspot_9class_best.pt ./
USER appuser
EXPOSE 7860
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860", "--workers", "1"]

