import pandas as pd
import numpy as np
import chromadb
import os
import json
import re
import matplotlib.pyplot as plt
import seaborn as sns

# --- AYARLAR ---
CHROMA_PATH = "./chroma_db"
JSON_DATA_PATH = "tmdb_content_10k.json"
CSV_FILE = "multi_user_ratings.csv"
COLLECTION_NAME = "content_vectors"
TEST_RATIO = 0.2 # Veri setimiz büyüdüğü için test oranını %20'ye çektim, daha çok eğitim verisi kalsın

def clean_title(title):
    if not title: return ""
    title = str(title).lower()
    title = re.sub(r'[^a-z0-9\s]', '', title)
    return title.strip()

def load_id_mapping(json_path):
    print(f">>> {json_path} üzerinden ID haritası çıkarılıyor...")
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    mapping = {clean_title(item.get('title') or item.get('name')): str(item['id']) for item in data if (item.get('title') or item.get('name'))}
    print(f"[INFO] Sözlükte {len(mapping)} film tanımlandı.")
    return mapping

def run_evaluation(df, id_map):
    client = chromadb.PersistentClient(path=CHROMA_PATH)
    collection = client.get_collection(name=COLLECTION_NAME)
    
    user_results = []

    for user in df['username'].unique():
        user_df = df[df['username'] == user]
        valid_vectors = []
        
        print(f"\n>>> {user} Analiz Ediliyor...")
        
        for _, row in user_df.iterrows():
            clean_t = clean_title(row['title'])
            tmdb_id = id_map.get(clean_t)
            
            if tmdb_id:
                try:
                    res = collection.get(ids=[tmdb_id], include=['embeddings'])
                    if len(res['ids']) > 0:
                        vector = np.array(res['embeddings'][0])
                        valid_vectors.append((vector, row['user_rating']))
                except:
                    continue

        if len(valid_vectors) < 10:
            print(f"   [!] {user}: Yeterli eşleşme yok (Eşleşen: {len(valid_vectors)}).")
            continue

        # Eğitim/Test Ayrımı
        split_idx = int(len(valid_vectors) * (1 - TEST_RATIO))
        train_data = valid_vectors[:split_idx]
        test_data = valid_vectors[split_idx:]
        
        # --- [TUNE NOKTASI] AĞIRLIKLI CENTROID HESABI ---
        # 8-10 Puan: x2.5 ağırlık (Zevki domine et)
        # 1-4 Puan: -1.0 ağırlık (Bu tarzdan uzaklaş)
        # 5-7 Puan: x0.5 ağırlık (Nötr etki)
        
        vector_dim = len(train_data[0][0])
        weighted_sum = np.zeros(vector_dim)
        total_weight = 0
        
        for vec, rating in train_data:
            if rating >= 8:
                w = 2.5
            elif rating <= 4:
                w = -1.0
            else:
                w = 0.5
            
            weighted_sum += vec * w
            total_weight += abs(w) # Normalizasyon için mutlak değer
            
        user_vector = weighted_sum / total_weight

        # Test: Puan Tahmini
        errors = []
        for v, real_rating in test_data:
            # Kosinüs Benzerliği
            dot = np.dot(user_vector, v)
            norm_u = np.linalg.norm(user_vector)
            norm_m = np.linalg.norm(v)
            similarity = dot / (norm_u * norm_m)
            
            # Tahmini 0-10 skalasına yayalım (Benzerliği normalize etme)
            # Similarity genelde -1 ile 1 arasıdır, biz bunu 0-10'a mapliyoruz
            predicted = (similarity + 1) * 5 
            predicted = max(0, min(10, predicted)) # 0-10 sınırında tut
            
            errors.append(abs(real_rating - predicted))
            
        mae = np.mean(errors)
        user_results.append({'username': user, 'MAE': mae})
        print(f"   [SUCCESS] {user} analizi bitti. MAE: {mae:.2f}")

    return pd.DataFrame(user_results)

def plot_results(report_df):
    if report_df.empty: return
    plt.figure(figsize=(12, 6))
    sns.set_theme(style="whitegrid")
    sns.barplot(x='username', y='MAE', data=report_df, palette='magma')
    
    global_mae = report_df['MAE'].mean()
    plt.axhline(global_mae, color='red', linestyle='--', label=f'Genel Ortalama: {global_mae:.2f}')
    
    plt.title('Finds Öneri Sistemi: Ağırlıklı Vektör Başarı Analizi', fontsize=16)
    plt.ylabel('MAE (Hata Payı)', fontsize=12)
    plt.xticks(rotation=45)
    plt.legend()
    plt.tight_layout()
    plt.savefig('evaluation_report_v2.png')
    plt.show()

if __name__ == "__main__":
    if os.path.exists(CSV_FILE) and os.path.exists(JSON_DATA_PATH):
        id_mapping = load_id_mapping(JSON_DATA_PATH)
        raw_data = pd.read_csv(CSV_FILE)
        results = run_evaluation(raw_data, id_mapping)
        
        if not results.empty:
            print("\n" + "="*30)
            print(f"GENEL SİSTEM MAE SKORU (AĞIRLIKLI): {results['MAE'].mean():.2f}")
            print("="*30)
            plot_results(results)