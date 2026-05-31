# Python'un hafif bir sürümünü kullan
FROM python:3.10-slim

# Çalışma klasörünü ayarla
WORKDIR /app

# Sistem gereksinimlerini kur (ChromaDB ve Transformers kütüphaneleri için şart)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Gereksinimleri kopyala ve kur
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Proje dosyalarını kopyala (chroma_db, app.py, firebase anahtarı)
COPY . .

# Cloud Run için portu 5000'e sabitliyoruz (gunicorn bu porttan dinleyecek)
ENV PORT 5000

# Flask'ı gunicorn ile 5000 portundan güvenli ve ölçeklenebilir şekilde ayağa kaldırıyoruz
CMD exec gunicorn --bind :5000 --workers 1 --threads 8 --timeout 0 app:app