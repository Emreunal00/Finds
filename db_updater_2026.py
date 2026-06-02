import requests
import chromadb
import time
from sentence_transformers import SentenceTransformer

# --- AYARLAR ---
TMDB_API_KEY = "b96a7f931a81af92f4742ecbdb4bef8d"
CHROMA_PATH = "./chroma_db"
COLLECTION_NAME = "content_vectors"

# Modeli ve DB'yi yükle
model = SentenceTransformer('all-MiniLM-L6-v2')
client = chromadb.PersistentClient(path=CHROMA_PATH)
collection = client.get_collection(name=COLLECTION_NAME)

def update_2026_movies():
    print(">>> 2026 filmleri TMDB'den çekiliyor (Güvenli Mod)...")
    new_entries = 0
    
    # İlk 5 sayfayı çekiyoruz (Toplam ~100 popüler film)
    for page in range(1, 6):
        print(f"\n--- Sayfa {page} taranıyor ---")
        url = f"https://api.themoviedb.org/3/discover/movie?api_key={TMDB_API_KEY}&primary_release_year=2026&sort_by=popularity.desc&page={page}"
        
        try:
            response = requests.get(url)
            
            # Rate Limit (429) Kontrolü
            if response.status_code == 429:
                print("[!] Hız sınırına takıldık. 10 saniye bekleniyor...")
                time.sleep(10)
                continue
            
            data = response.json()
            movies = data.get('results', [])
            
            if not movies:
                print("Daha fazla film bulunamadı.")
                break
            
            for movie in movies:
                m_id = str(movie['id'])
                title = movie['title']
                overview = movie['overview']
                
                if not overview: 
                    continue # Özet yoksa vektör sağlıklı olmaz
                
                # DB'de var mı kontrol et
                existing = collection.get(ids=[m_id])
                if not existing['ids']:
                    # Vektörleme
                    text_content = f"{title} {overview}"
                    embedding = model.encode(text_content).tolist()
                    
                    collection.add(
                        ids=[m_id],
                        embeddings=[embedding],
                        metadatas=[{"title": title, "year": "2026"}]
                    )
                    new_entries += 1
                    print(f"   [+] DB'ye Eklendi: {title}")
                else:
                    # Zaten varsa ekrana kalabalık yapmasın diye sadece log geçebilirsin
                    pass
            
            # Sayfa arası 1 saniye bekle (Hız koruması)
            time.sleep(1)
            
        except Exception as e:
            print(f"   [!] Hata: {e}")
            break
            
    print(f"\n>>> İşlem tamam. Toplam {new_entries} adet yeni 2026 filmi eklendi.")

if __name__ == "__main__":
    update_2026_movies()