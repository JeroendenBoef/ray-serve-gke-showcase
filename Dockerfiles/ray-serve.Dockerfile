FROM rayproject/ray-ml:2.9.0-py310-gpu

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
      --index-url https://download.pytorch.org/whl/cu118 \
      torch==2.1.2+cu118 torchvision==0.16.2+cu118 torchaudio==2.1.2+cu118 && \
    pip install --no-cache-dir "transformers==4.51.3"

WORKDIR /opt
COPY apps/ray/serve_app/serve_app.py /opt/serve_app.py

ENV PYTHONPATH=/opt
