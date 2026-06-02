# Python'un hafif bir sürümünü kullan
FROM python:3.10-slim

# Çalışma klasörünü ayarla
WORKDIR /app

# Sistem gereksinimlerini kur (Bazı kütüphaneler için gerekebilir)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Gereksinimleri kopyala ve kur
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Proje dosyalarını kopyala
# (Önemli: chroma_db klasörün ve firebase anahtarın da buraya kopyalanacak)
COPY . .

# Flask'ın portunu ayarla (Cloud Run 8080 sever)
ENV PORT 8080

# Uygulamayı başlat
CMD ["python", "app.py"]