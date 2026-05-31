# -*- coding: utf-8 -*-
import os
import json 
import datetime
import random
from datetime import timedelta 
from flask import Flask, jsonify, request
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, firestore
import chromadb
from sentence_transformers import SentenceTransformer
import numpy as np 
import traceback 
import google.generativeai as genai

# --- 1. KURULUM VE YAPILANDIRMA ---
load_dotenv()
app = Flask(__name__)

# Sabitler
FIRESTORE_COLLECTION = "content"
CHROMA_COLLECTION = "content_vectors"
CANDIDATE_POOL_SIZE = 2000
MAX_REC_LIMIT = 30 
DEFAULT_API_COUNT = 30 
DEFAULT_CHAT_COUNT = 5 
SESSION_TIMEOUT_MINUTES = 30 
TASTE_VECTOR_WEIGHT = 0.7  # Kullanıcı zevki baskın
QUERY_VECTOR_WEIGHT = 0.3  # Anlık sorgu etkisi

# Dil ve Mood Haritaları
GENRE_MAP = {
    "bilim kurgu": "science fiction", "sci-fi": "science fiction", "tv filmi": "tv movie",
    "aksiyon": "action", "macera": "adventure", "animasyon": "animation",
    "komedi": "comedy", "suç": "crime", "belgesel": "documentary",
    "dram": "drama", "aile": "family", "fantastik": "fantasy",
    "tarih": "history", "korku": "horror", "müzik": "music",
    "gizem": "mystery", "romantik": "romance", 
    "gerilim": "thriller", "savaş": "war", "western": "western"
}

# Modeller ve DB Bağlantıları
genai.configure(api_key=os.getenv('GEMINI_API_KEY'))
ai_model = genai.GenerativeModel('gemini-2.0-flash') 

if not firebase_admin._apps:
    cred = credentials.Certificate(os.getenv('FIREBASE_KEY_PATH'))
    firebase_admin.initialize_app(cred)
db = firestore.client()
users_collection = db.collection('users')
content_collection = db.collection(FIRESTORE_COLLECTION)

client = chromadb.PersistentClient(path="./chroma_db")
chroma_collection = client.get_collection(name=CHROMA_COLLECTION)
model = SentenceTransformer('all-MiniLM-L6-v2')

# --- 2. ÇEKİRDEK YARDIMCI FONKSİYONLAR ---

def extract_ids_from_entries(entries):
    ids = []
    if not entries: return ids
    for entry in entries:
        if isinstance(entry, dict) and entry.get('id'): ids.append(str(entry.get('id')))
        elif isinstance(entry, str): ids.append(entry)
    return ids

def get_content_from_firestore(ids_list):
    if not ids_list: return {}
    content_data = {}
    unique_ids = list(set(ids_list))
    for i in range(0, len(unique_ids), 30):
        chunk_ids = unique_ids[i:i+30]
        try:
            docs = content_collection.where(field_path=u"__name__", op_string='in', value=chunk_ids).stream()
            for doc in docs:
                content_data[doc.id] = doc.to_dict()
        except: continue
    return content_data

def calculate_weighted_taste_vector(user_data, content_meta):
    """
    MAE 1.95 skoru getiren Ağırlıklı Centroid hesaplaması.
    """
    # Etkileşim türlerini al
    fav_ids = set(extract_ids_from_entries(user_data.get('favoritesEntries', [])))
    watched_entries = user_data.get('watchedEntries', [])
    watched_ids = set(extract_ids_from_entries(watched_entries))
    other_ids = set(extract_ids_from_entries(user_data.get('watchlistEntries', [])) + 
                    extract_ids_from_entries(user_data.get('onboardingSelections', [])))
    
    all_ids = list(fav_ids | watched_ids | other_ids)
    valid_ids = [uid for uid in all_ids if uid in content_meta]
    
    if not valid_ids: return np.zeros(384)

    try:
        vec_data = chroma_collection.get(ids=valid_ids, include=['embeddings'])
        id_to_vec = {id: np.array(emb) for id, emb in zip(vec_data['ids'], vec_data['embeddings'])}
    except: return np.zeros(384)

    weighted_sum = np.zeros(384)
    total_weight = 0

    for uid in valid_ids:
        if uid not in id_to_vec: continue
        vec = id_to_vec[uid]
        
        # Puanı bul (watchedEntries içinden)
        user_rating = 0
        for entry in watched_entries:
            if str(entry.get('id')) == uid:
                user_rating = float(entry.get('rating', 0))
                break
        
        # Ağırlıklandırma Mantığı (Tune Edilmiş)
        if user_rating >= 8:
            weight = 2.5   # Çok sevdikleri
        elif 0 < user_rating <= 4:
            weight = -1.0  # Sevmedikleri (Negatif itiş)
        elif uid in fav_ids:
            weight = 2.0   # Favoriler
        else:
            weight = 0.5   # Nötr veya merak edilenler
            
        weighted_sum += vec * weight
        total_weight += abs(weight)

    return weighted_sum / total_weight if total_weight > 0 else np.zeros(384)

def analyze_query_with_gemini(query):
    """
    Kullanıcının doğal dilde yazdığı chatbot sorgusunu Gemini 2.0 ile analiz edip
    intent (niyet) ve filtreleri (tür, yıl) çıkartan fonksiyon.
    """
    prompt = f"""
    Kullanıcının şu mesajını analiz et: "{query}"
    
    Eğer kullanıcı film/dizi/içerik önerisi istiyorsa (Örn: "bana aksiyon öner", "film tavsiye et", "ne izlesem"):
    - intent değerini "recommendation" yap.
    - Kullanıcının belirttiği türleri (genres) bir liste olarak çıkar (Örn: ["Aksiyon", "Bilim Kurgu"]).
    - Yıl sınırları varsa 'year_min' ve 'year_max' olarak belirt (Örn: 2010 sonrası için year_min: 2010).
    
    Eğer kullanıcı öneri istemiyor, sadece genel bir sohbet ediyorsa (Örn: "merhaba", "nasılsın", "sen kimsin"):
    - intent değerini "chat" yap.
    - 'reply_text' alanına samimi, eğlenceli ve sinemasever bir yapay zeka gibi Türkçe bir yanıt yaz.
    
    Sadece ve sadece aşağıdaki JSON formatında yanıt dön, başka hiçbir açıklama yazma:
    {{
        "intent": "recommendation" veya "chat",
        "filters": {{
            "genres": [],
            "year_min": null veya int,
            "year_max": null veya int
        }},
        "reply_text": "Sohbet mesajı yanıtı veya boş string"
    }}
    """
    try:
        response = ai_model.generate_content(prompt)
        # Markdown ```json ``` kalıntılarını temizleme zırhı
        clean_text = response.text.replace("```json", "").replace("```", "").strip()
        return json.loads(clean_text)
    except Exception as e:
        print(f"[-] Gemini sorgu analizi sırasında hata oluştu: {e}")
        # Hata durumunda sistemi çökertmemek için fallback mekanizması
        return {
            "intent": "recommendation",
            "filters": {"genres": [], "year_min": None, "year_max": None},
            "reply_text": ""
        }

# --- 3. ANA ÖNERİ MANTIĞI ---

def get_chatbot_recommendations_logic(is_chatbot=False):
    user_id = request.args.get('userId')
    query = request.args.get('query')
    raw_type = request.args.get('type')
    
    if not user_id: return jsonify({"error": "userId gerekli."}), 400

    # Kullanıcı verilerini ve Taste Vector'ü hazırla
    try:
        user_doc = users_collection.document(user_id).get()
        user_data = user_doc.to_dict() if user_doc.exists else {}
        
        all_relevant_ids = list(set(extract_ids_from_entries(user_data.get('favoritesEntries', [])) + 
                                    extract_ids_from_entries(user_data.get('watchedEntries', []))))
        meta_data = get_content_from_firestore(all_relevant_ids)
        taste_vector = calculate_weighted_taste_vector(user_data, meta_data)
    except:
        taste_vector = np.zeros(384)

    # Chatbot Analizi ve Filtreleme
    genre_filters, safe_type = [], raw_type.lower() if raw_type else None
    year_min, year_max = None, None
    final_search_vector = taste_vector

    if is_chatbot and query:
        # Gemini analizi (kodun önceki kısımlarındaki analyze_query_with_gemini fonksiyonu varsayıldı)
        ai_res = analyze_query_with_gemini(query) 
        if ai_res.get('intent') != 'recommendation':
            return jsonify({"bot_message": ai_res.get('reply_text'), "recommendations": []})
        
        filters = ai_res.get('filters', {})
        genre_filters = [GENRE_MAP.get(g.lower(), g.lower()) for g in filters.get('genres', [])]
        year_min, year_max = filters.get('year_min'), filters.get('year_max')
        
        query_vector = model.encode(query)
        final_search_vector = (TASTE_VECTOR_WEIGHT * taste_vector) + (QUERY_VECTOR_WEIGHT * query_vector)

    # ChromaDB Sorgusu
    query_results = chroma_collection.query(
        query_embeddings=[final_search_vector.tolist()],
        n_results=CANDIDATE_POOL_SIZE,
        include=['distances']
    )
    
    cand_ids = query_results['ids'][0]
    distances = query_results['distances'][0]
    all_cand_meta = get_content_from_firestore(cand_ids)
    
    watched_ids = set(extract_ids_from_entries(user_data.get('watchedEntries', [])))
    final_candidates = []

    for i, cid in enumerate(cand_ids):
        if cid in watched_ids or cid not in all_cand_meta: continue
        cand = all_cand_meta[cid]
        
        # Tip ve Yıl Filtreleri
        c_type = cand.get('type', '').lower()
        if safe_type and c_type and c_type not in safe_type: continue
        
        try: cy = int(cand.get('year', 0))
        except: cy = 0
        if year_min and cy < year_min: continue
        if year_max and cy > year_max: continue

        # Tür Filtresi
        if genre_filters:
            c_genres = {g.lower() for g in cand.get('genres', [])}
            if not c_genres.intersection(set(genre_filters)): continue

        # Skorlama (1.95 MAE Formülü)
        cosine_sim = 1 - (distances[i] / 2.0)
        norm_sim = (cosine_sim + 1) * 5 # 0-10 skalası
        tmdb_rating = float(cand.get('rating', 0))
        
        final_score = (norm_sim * 0.7) + (tmdb_rating * 0.3)
        final_candidates.append({**cand, "content_id": cid, "final_score": round(final_score, 2)})

    # Sonuçları Sırala ve Döndür
    sorted_recs = sorted(final_candidates, key=lambda x: x['final_score'], reverse=True)
    count = DEFAULT_CHAT_COUNT if is_chatbot else DEFAULT_API_COUNT
    return jsonify({"bot_message": "İşte senin için seçtiklerim:", "recommendations": sorted_recs[:count]})

# --- 4. ENDPOINTS ---
@app.route('/api/v1/recommendations', methods=['GET'])
def get_recommendations(): return get_chatbot_recommendations_logic(is_chatbot=False)

@app.route('/api/v1/chatbot', methods=['GET'])
def get_chatbot_recommendations(): return get_chatbot_recommendations_logic(is_chatbot=True)


# --- 5. TÜR BAZLI KİTAP ÖNERİ SİSTEMİ (YENİ FEATURE) ---

try:
    book_chroma_collection = client.get_collection(name="book_vectors")
    print("[+] Kitap koleksiyonu (book_vectors) başarıyla app.py'ye bağlandı.")
except Exception as e:
    print(f"[-] UYARI: Kitap koleksiyonu yüklenemedi. Hata: {e}")

@app.route('/api/v1/book-recommendations', methods=['GET'])
def get_book_recommendations():
    """
    Kullanıcının en çok sevdiği film türlerini analiz edip, 
    kitap havuzundan o türle eşleşen popüler kitapları getiren pratik endpoint.
    """
    user_id = request.args.get('userId')
    count_param = request.args.get('count', default=15)
    
    if not user_id: 
        return jsonify({"error": "userId parametresi gerekli."}), 400
        
    try:
        target_count = int(count_param)
    except:
        target_count = 5

    try:
        # 1. Aşama: Kullanıcının film verilerini Firestore'dan çek
        user_doc = users_collection.document(user_id).get()
        if not user_doc.exists:
            return jsonify({"status": "success", "message": "Kullanıcı bulunamadı.", "books": []})
            
        user_data = user_doc.to_dict()
        watched_entries = user_data.get('watchedEntries', [])
        favorites_entries = user_data.get('favoritesEntries', [])

        # 2. Aşama: Kullanıcının yüksek puanlı (>=7) veya favorilerdeki filmlerini topla
        loved_movie_ids = []
        for entry in favorites_entries:
            loved_movie_ids.append(str(entry.get('id')) if isinstance(entry, dict) else str(entry))
            
        for entry in watched_entries:
            if isinstance(entry, dict) and float(entry.get('rating', 0)) >= 7:
                loved_movie_ids.append(str(entry.get('id')))

        # Cold Start Durumu: Kullanıcının geçmişi yoksa genel popüler kitaplardan dön
        if not loved_movie_ids:
            results = book_chroma_collection.get(limit=target_count, include=['metadatas'])
            books = []
            for i in range(len(results['ids'])):
                books.append({
                    "book_id": results['ids'][i],
                    "title": results['metadatas'][i].get('title', 'Kült Kitap'),
                    "authors": results['metadatas'][i].get('authors', 'Bilinmeyen Yazar'),
                    "genre": results['metadatas'][i].get('genre', 'Genel'),
                    "image_url": results['metadatas'][i].get('image_url', ''),
                    "match_score": 7.5
                })
            return jsonify({"status": "success", "message": "Popüler kitaplar listelendi.", "books": books})

        # 3. Aşama: Bu filmlerin türlerini Firestore'dan eşleştir ve en baskın türü bul
        movie_meta = get_content_from_firestore(loved_movie_ids)
        user_favorite_genres = []
        
        for mid in loved_movie_ids:
            if mid in movie_meta:
                genres = movie_meta[mid].get('genres', [])
                user_favorite_genres.extend([g.lower() for g in genres])

        if not user_favorite_genres:
            user_favorite_genres = ["fiction"]

        # En çok tekrar eden film türünü yakala
        most_common_genre = max(set(user_favorite_genres), key=user_favorite_genres.count)
        
        # İngilizce haritalandırma kontrolü (ChromaDB kitap türleri uyumu için)
        mapped_genre = GENRE_MAP.get(most_common_genre, most_common_genre)

        # 4. Aşama: En çok sevilen tür vektörünü kitap odasında sorgula
        query_vector = model.encode(mapped_genre).tolist()
        
        query_results = book_chroma_collection.query(
            query_embeddings=[query_vector],
            n_results=target_count,
            include=['metadatas', 'distances']
        )
        
        cand_ids = query_results['ids'][0]
        distances = query_results['distances'][0]
        metadatas = query_results['metadatas'][0]
        
        final_books = []
        for i in range(len(cand_ids)):
            cosine_sim = 1 - (distances[i] / 2.0)
            match_score = round((cosine_sim + 1) * 5, 2)
            
            final_books.append({
                "book_id": cand_ids[i],
                "title": metadatas[i].get('title', 'Bilinmeyen Kitap'),
                "authors": metadatas[i].get('authors', 'Bilinmeyen Yazar'),
                "genre": metadatas[i].get('genre', 'Genel'),
                "published_year": metadatas[i].get('published_year', 'N/A'),
                "image_url": metadatas[i].get('image_url', ''),
                "match_score": match_score
            })
            
        return jsonify({
            "status": "success",
            "user_id": user_id,
            "matched_genre": mapped_genre,
            "message": f"En çok izlediğin '{mapped_genre}' tarzına uygun kitaplar seçildi.",
            "books": final_books
        })
        
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": f"Kitaplar sorgulanırken hata oluştu: {str(e)}"}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)