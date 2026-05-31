# -*- coding: utf-8 -*-
import os
import time
import requests
import chromadb
from dotenv import load_dotenv
from sentence_transformers import SentenceTransformer

# --- CONFIG AND SETTINGS ---
load_dotenv()
GOOGLE_API_KEY = os.getenv('GOOGLE_BOOKS_API_KEY')
CHROMA_PATH = "./chroma_db"
COLLECTION_NAME = "book_vectors"

if not GOOGLE_API_KEY:
    print("[HATA] GOOGLE_BOOKS_API_KEY .env dosyasında bulunamadı!")
    exit()

print(">>> Embedding modeli ve ChromaDB yükleniyor...")
model = SentenceTransformer('all-MiniLM-L6-v2')
client = chromadb.PersistentClient(path=CHROMA_PATH)

# CRITICAL UPDATE: Silme (delete) bloğu kaldırıldı! 
# Koleksiyon varsa içine girer, yoksa sıfırdan oluşturur.
collection = client.get_or_create_collection(name=COLLECTION_NAME)

# Bilinen kitapları tetikleyecek popüler arama keyword'leri
POPULAR_QUERIES = [
    "subject:fiction+bestseller", 
    "subject:science_fiction+popular", 
    "subject:mystery+bestseller", 
    "subject:thriller+popular", 
    "subject:fantasy+bestseller", 
    "star_wars+dune+lord_of_the_rings", 
    "subject:history+popular", 
    "subject:biography+bestseller", 
    "subject:business+bestseller", 
    "subject:psychology+popular"
]

def fetch_and_load_books():
    print(">>> Google Books API üzerinden Mevcut Havuzun Üstüne Ekleme Başlıyor...")
    total_inserted = 0
    request_count = 0
    
    for query in POPULAR_QUERIES:
        print(f"\n--- Sorgu Çalıştırılıyor: {query} ---")
        
        for page in range(3):
            start_index = page * 40
            url = f"https://www.googleapis.com/books/v1/volumes?q={query}&maxResults=40&startIndex={start_index}&orderBy=relevance&key={GOOGLE_API_KEY}"
            
            try:
                time.sleep(2)  # Saniyede 1 istek zırhı
                
                response = requests.get(url)
                request_count += 1
                
                if response.status_code == 429:
                    print("[!] Google hız sınırına takıldık! 15 saniye mola...")
                    time.sleep(15)
                    continue
                    
                if response.status_code != 200:
                    print(f"[!] API Hatası ({response.status_code}), geçiliyor.")
                    continue
                    
                data = response.json()
                items = data.get('items', [])
                
                if not items:
                    break
                    
                for item in items:
                    b_id = item.get('id')
                    volume_info = item.get('volumeInfo', {})
                    
                    title = volume_info.get('title')
                    description = volume_info.get('description', '')
                    authors = ", ".join(volume_info.get('authors', []))
                    genres = ", ".join(volume_info.get('categories', []))
                    pub_date = volume_info.get('publishedDate', '')
                    
                    # 1970 kontrolü
                    try:
                        pub_year = int(pub_date[:4]) if pub_date else 0
                    except:
                        pub_year = 0
                        
                    if pub_year < 1970 or not title or not description:
                        continue
                    
                    # ZIRH: DB'de bu kitap ID'si var mı kontrol et
                    existing = collection.get(ids=[b_id])
                    if len(existing['ids']) == 0:
                        text_content = f"Book Title: {title} | Author: {authors} | Genre: {genres} | Published: {pub_year} | Description: {description}"
                        embedding = model.encode(text_content).tolist()
                        
                        metadata = {
                            "title": title,
                            "authors": authors if authors else "Unknown",
                            "genre": genres if genres else "General",
                            "published_year": str(pub_year),
                            "image_url": volume_info.get('imageLinks', {}).get('thumbnail', '')
                        }
                        
                        collection.add(
                            ids=[b_id],
                            embeddings=[embedding],
                            metadatas=[metadata]
                        )
                        total_inserted += 1
                        print(f"   [+] ({pub_year}) Yeni Popüler Kitap Eklendi: {title}")
                    else:
                        # Eğer kitap zaten varsa terminali kirletmemek için sessizce geçiyor
                        pass
                
            except Exception as e:
                print(f"   [!] Hata: {e}")
                continue

    print("\n" + "="*40)
    print(f">>> İŞLEM TAMAMLANDI!")
    print(f">>> Toplam Harcanan İstek: {request_count}")
    print(f">>> Bu Turda Eklenen YENİ Kitap Sayısı: {total_inserted}")
    print(f">>> Önceki kitaplar korundu, yeni popülerler üzerine yazıldı.")
    print("="*40)

if __name__ == "__main__":
    fetch_and_load_books()