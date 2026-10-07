FROM python:3.11-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# OpenCV (pulled in by ultralytics) imports its GUI backend at import time and
# needs these shared libraries, none of which exist on python:slim.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
        libgomp1 \
        libxcb1 \
        libxext6 \
        libxrender1 \
        libsm6 \
    && rm -rf /var/lib/apt/lists/*

# Torch on CPU only. The default PyPI wheel bundles CUDA libs (multi-GB) that
# Render's free CPU instances cannot use; the CPU wheel keeps the image small
# enough for the free container disk and is what ulralytics actually runs on.
RUN pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu

COPY requirements.txt .
RUN pip install -r requirements.txt

# Only the model the API serves by default ships in the image (38 MB);
# MODEL_FILE can still override the filename in the container.
COPY app.py .
COPY farmspot_9class_best.pt .

EXPOSE 8001

# Render injects $PORT; default to 8001 for local/dev runs.
CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT:-8001}"]