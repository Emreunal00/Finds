# -*- coding: utf-8 -*-
import os
import json 
import datetime
import random
import re
from datetime import timedelta 
from flask import Flask, jsonify, request
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, firestore
from google.cloud.firestore_v1.field_path import FieldPath
import chromadb
from sentence_transformers import SentenceTransformer
import numpy as np 
import traceback 
from groq import Groq  

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
TASTE_VECTOR_WEIGHT = 0.7  
QUERY_VECTOR_WEIGHT = 0.3  

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

CONTENT_TYPE_ALIASES = {
    "movie": "movie", "film": "movie", "sinema": "movie",
    "tv": "tv", "dizi": "tv", "series": "tv", "show": "tv",
    "book": "book", "kitap": "book", "roman": "book"
}

GENRE_FILTER_MAP = {
    "bilim kurgu": ["science fiction", "sci-fi & fantasy"],
    "sci-fi": ["science fiction", "sci-fi & fantasy"],
    "science fiction": ["science fiction", "sci-fi & fantasy"],
    "aksiyon": ["action", "action & adventure"],
    "action": ["action", "action & adventure"],
    "macera": ["adventure", "action & adventure"],
    "adventure": ["adventure", "action & adventure"],
    "animasyon": ["animation"],
    "animation": ["animation"],
    "komedi": ["comedy"],
    "comedy": ["comedy"],
    "suç": ["crime"],
    "crime": ["crime"],
    "belgesel": ["documentary"],
    "documentary": ["documentary"],
    "dram": ["drama"],
    "drama": ["drama"],
    "aile": ["family"],
    "family": ["family"],
    "fantastik": ["fantasy", "sci-fi & fantasy"],
    "fantasy": ["fantasy", "sci-fi & fantasy"],
    "tarih": ["history"],
    "history": ["history"],
    "korku": ["horror"],
    "horror": ["horror"],
    "müzik": ["music"],
    "music": ["music"],
    "gizem": ["mystery"],
    "mystery": ["mystery"],
    "romantik": ["romance"],
    "romance": ["romance"],
    "gerilim": ["thriller"],
    "thriller": ["thriller"],
    "savaş": ["war", "war & politics"],
    "war": ["war", "war & politics"],
    "western": ["western"],
    "çocuk": ["kids", "family"],
    "kids": ["kids", "family"]
}

CHAT_TRIGGERS = {"merhaba", "selam", "naber", "nasılsın", "kimsin"}
RECOMMENDATION_TRIGGERS = (
    "öner", "tavsiye", "ne izlesem", "ne okusam", "izlemelik",
    "okumalık", "benzer", "seç", "bul"
)

# Modeller ve DB Bağlantıları
SERVICE_STATUS = {
    "firebase": False,
    "chroma": False,
    "content_vectors": False,
    "sentence_model": False,
    "groq": False,
    "local_content_cache": False,
}
SERVICE_ERRORS = {}

def mark_service(name, ok, error=None):
    SERVICE_STATUS[name] = ok
    if error:
        SERVICE_ERRORS[name] = str(error)
    else:
        SERVICE_ERRORS.pop(name, None)

def parse_bool_env(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}

groq_api_key = os.getenv('GROQ_API_KEY')
groq_client = Groq(api_key=groq_api_key) if groq_api_key else None
mark_service("groq", bool(groq_client), None if groq_client else "GROQ_API_KEY bulunamadı; yerel sorgu analizi kullanılacak.")

db = None
users_collection = None
content_collection = None
firebase_key_path = os.getenv('FIREBASE_KEY_PATH')
try:
    if not firebase_key_path:
        raise RuntimeError("FIREBASE_KEY_PATH .env içinde tanımlı değil.")
    if not firebase_admin._apps:
        cred = credentials.Certificate(firebase_key_path)
        firebase_admin.initialize_app(cred)
    db = firestore.client()
    users_collection = db.collection('users')
    content_collection = db.collection(FIRESTORE_COLLECTION)
    mark_service("firebase", True)
except Exception as e:
    print(f"[-] Firebase başlatılamadı: {e}")
    mark_service("firebase", False, e)

client = None
chroma_collection = None
try:
    client = chromadb.PersistentClient(path="./chroma_db")
    mark_service("chroma", True)
    chroma_collection = client.get_collection(name=CHROMA_COLLECTION)
    mark_service("content_vectors", True)
except Exception as e:
    print(f"[-] Chroma/content_vectors başlatılamadı: {e}")
    if client is None:
        mark_service("chroma", False, e)
    mark_service("content_vectors", False, e)

model = None
try:
    model = SentenceTransformer('all-MiniLM-L6-v2')
    mark_service("sentence_model", True)
except Exception as e:
    print(f"[-] SentenceTransformer modeli yüklenemedi: {e}")
    mark_service("sentence_model", False, e)

def load_local_content_cache():
    try:
        with open("tmdb_content_10k.json", "r", encoding="utf-8") as f:
            items = json.load(f)
        mark_service("local_content_cache", True)
        return {str(item.get("id")): item for item in items if item.get("id")}
    except Exception as e:
        print(f"[-] Yerel içerik yedeği yüklenemedi: {e}")
        mark_service("local_content_cache", False, e)
        return {}

LOCAL_CONTENT_CACHE = load_local_content_cache()

# --- 2. ÇEKİRDEK YARDIMCI FONKSİYONLAR ---

def service_unavailable_response(service_name, message=None):
    return jsonify({
        "status": "error",
        "error": message or f"{service_name} hazır değil.",
        "service": service_name,
        "details": SERVICE_ERRORS.get(service_name)
    }), 503

def normalize_count(value, default_count, max_count=MAX_REC_LIMIT):
    if value in (None, ""):
        return default_count
    try:
        requested = int(str(value).strip())
    except (TypeError, ValueError):
        return default_count
    return max(1, min(requested, max_count))

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
    if content_collection is not None:
        for i in range(0, len(unique_ids), 30):
            chunk_ids = unique_ids[i:i+30]
            try:
                # Sapsarı yanan UserWarning hatasını engellemek için filter keyword kuralına uyarlandı 
                chunk_refs = [content_collection.document(uid) for uid in chunk_ids]
                docs = content_collection.where(
                    filter=firestore.FieldFilter(FieldPath.document_id(), "in", chunk_refs)
                ).stream()
                for doc in docs:
                    content_data[doc.id] = doc.to_dict()
            except Exception as e:
                print(f"[-] Firestore içerik çekme hatası ({chunk_ids[:3]}...): {e}")
                continue

    missing_ids = [uid for uid in unique_ids if uid not in content_data]
    for uid in missing_ids:
        if uid in LOCAL_CONTENT_CACHE:
            content_data[uid] = LOCAL_CONTENT_CACHE[uid]

    return content_data

def calculate_weighted_taste_vector(user_data, content_meta):
    """
    Kullanıcı etkileşimlerinden ağırlıklı zevk vektörü hesaplar.
    """
    fav_ids = set(extract_ids_from_entries(user_data.get('favoritesEntries', [])))
    watched_entries = user_data.get('watchedEntries', [])
    watched_ids = set(extract_ids_from_entries(watched_entries))
    other_ids = set(extract_ids_from_entries(user_data.get('watchlistEntries', [])) + 
                    extract_ids_from_entries(user_data.get('onboardingSelections', [])))
    
    all_ids = list(fav_ids | watched_ids | other_ids)
    valid_ids = [uid for uid in all_ids if uid in content_meta]
    
    if not valid_ids: return np.zeros(384)
    if chroma_collection is None: return np.zeros(384)

    try:
        vec_data = chroma_collection.get(ids=valid_ids, include=['embeddings'])
        id_to_vec = {id: np.array(emb) for id, emb in zip(vec_data['ids'], vec_data['embeddings'])}
    except: return np.zeros(384)

    weighted_sum = np.zeros(384)
    total_weight = 0

    for uid in valid_ids:
        if uid not in id_to_vec: continue
        vec = id_to_vec[uid]
        
        user_rating = 0
        for entry in watched_entries:
            if str(entry.get('id')) == uid:
                user_rating = float(entry.get('rating', 0))
                break
        
        if user_rating >= 8:
            weight = 2.5   
        elif 0 < user_rating <= 4:
            weight = -1.0  
        elif uid in fav_ids:
            weight = 2.0   
        else:
            weight = 0.5   
            
        weighted_sum += vec * weight
        total_weight += abs(weight)

    return weighted_sum / total_weight if total_weight > 0 else np.zeros(384)

def normalize_content_type(value, default="movie"):
    if not value:
        return default

    normalized = str(value).strip().lower()
    if normalized in CONTENT_TYPE_ALIASES:
        return CONTENT_TYPE_ALIASES[normalized]

    return default

def has_any_pattern(text, patterns):
    return any(re.search(pattern, text, flags=re.IGNORECASE) for pattern in patterns)

def detect_content_type_from_query(query, default="movie"):
    q = (query or "").strip().lower()

    movie_patterns = [
        r"\bfilm(?:i|ler|leri)?\b",
        r"\bsinema\b",
        r"\bmovie(?:s)?\b",
        r"\bizle(?:mek|melik|sem|yeyim|yecek)?\b",
    ]
    tv_patterns = [
        r"\bdizi(?:si|ler|leri)?\b",
        r"\bseries\b",
        r"\bshow\b",
        r"\btv\b",
    ]
    book_patterns = [
        r"\bkitap(?:ı|i|lar|ları)?\b",
        r"\broman(?:ı|i|a|e|da|de|dan|den|lar|ları)?\b",
        r"\bbook(?:s)?\b",
        r"\bok(?:u|umak|uyacak|umalık|usam|uyayım)\b",
        r"\bne okusam\b",
    ]

    if has_any_pattern(q, movie_patterns):
        return "movie"
    if has_any_pattern(q, tv_patterns):
        return "tv"
    if has_any_pattern(q, book_patterns):
        return "book"

    return default

def extract_requested_count(query, default_count):
    q = (query or "").lower()
    match = (
        re.search(r"\b(\d{1,2})(?!\s*[\.\)])\s*(?:tane|adet|film|dizi|kitap|öneri)\b", q)
        or re.search(r"\b(\d{1,2})(?!\s*[\.\)])\s+\w+\s+(?:film|dizi|kitap)\b", q)
        or re.search(r"^\s*(\d{1,2})(?!\s*[\.\)])\b", q)
    )
    if not match:
        return default_count

    try:
        requested = int(match.group(1))
    except ValueError:
        return default_count

    return max(1, min(requested, MAX_REC_LIMIT))

def normalize_year(value):
    if value in (None, ""):
        return None
    try:
        year = int(value)
        return year if 1800 <= year <= 2100 else None
    except (TypeError, ValueError):
        return None

def normalize_genres_value(genres):
    if isinstance(genres, str):
        genres = genres.split(",")
    if not isinstance(genres, list):
        return []
    return [str(g).strip().lower() for g in genres if str(g).strip()]

def expand_genre_filters(genres):
    expanded = []
    for genre in normalize_genres_value(genres):
        mapped = GENRE_FILTER_MAP.get(genre) or [GENRE_MAP.get(genre, genre)]
        expanded.extend(mapped)
    return list(dict.fromkeys(g.lower() for g in expanded if g))

def analyze_query_locally(query):
    q = (query or "").strip().lower()
    genres = []

    for keyword in sorted(GENRE_FILTER_MAP.keys(), key=len, reverse=True):
        if keyword in q:
            genres.append(keyword)

    has_recommendation_word = any(trigger in q for trigger in RECOMMENDATION_TRIGGERS)
    has_content_hint = bool(genres) or detect_content_type_from_query(q, None) is not None
    is_chat_only = q in CHAT_TRIGGERS or (any(trigger in q for trigger in CHAT_TRIGGERS) and not has_content_hint)
    intent = "chat" if is_chat_only and not has_recommendation_word else "recommendation"

    content_type = detect_content_type_from_query(q, "movie")

    year_min = None
    year_max = None
    after_match = re.search(r"(\d{4})(?:'?\s*d[ae]n)?\s*(?:sonra|sonrası|üstü)", q)
    before_match = re.search(r"(\d{4})(?:'?\s*d[ae]n)?\s*(?:önce|öncesi|altı)", q)
    if after_match:
        year_min = normalize_year(after_match.group(1))
    if before_match:
        year_max = normalize_year(before_match.group(1))

    return {
        "intent": intent,
        "content_type": content_type,
        "filters": {
            "genres": list(dict.fromkeys(genres)),
            "year_min": year_min,
            "year_max": year_max
        },
        "reply_text": "" if intent == "recommendation" else "Buradayım. Film, dizi ya da kitap için zevkine göre öneri hazırlayabilirim."
    }

def normalize_ai_response(ai_res, query):
    local_res = analyze_query_locally(query)
    if not isinstance(ai_res, dict):
        return local_res

    intent = str(ai_res.get("intent", local_res["intent"])).strip().lower()
    if intent not in {"recommendation", "chat"}:
        intent = local_res["intent"]

    # Kullanıcı öneri kelimesi yazdıysa Groq'un yanlışlıkla chat demesi boş liste üretiyordu.
    query_lower = (query or "").lower()
    if any(trigger in query_lower for trigger in RECOMMENDATION_TRIGGERS):
        intent = "recommendation"

    groq_type = normalize_content_type(ai_res.get("content_type"), local_res["content_type"])
    explicit_query_type = detect_content_type_from_query(query, None)
    content_type = explicit_query_type or groq_type

    filters = ai_res.get("filters") if isinstance(ai_res.get("filters"), dict) else {}
    groq_genres = normalize_genres_value(filters.get("genres", []))
    local_genres = local_res["filters"]["genres"]
    genres = list(dict.fromkeys(groq_genres + local_genres))

    return {
        "intent": intent,
        "content_type": content_type,
        "filters": {
            "genres": genres,
            "year_min": normalize_year(filters.get("year_min")) or local_res["filters"]["year_min"],
            "year_max": normalize_year(filters.get("year_max")) or local_res["filters"]["year_max"]
        },
        "reply_text": ai_res.get("reply_text") or local_res["reply_text"]
    }

def analyze_query_with_gemini(query):
    """
    Kullanıcının doğal dilde yazdığı chatbot sorgusunu Llama 3.1 (Groq) ile analiz eder.
    Metod ismini bozmadık ki projenin frontend bağlantıları veya çağrı yerleri patlamasın .
    """
    if not groq_client:
        print("[-] GROQ_API_KEY bulunamadı. Yerel sorgu analizi kullanılacak.")
        return analyze_query_locally(query)

    prompt = f"""
    Kullanıcının şu mesajını analiz et: "{query}"
    
    Kullanıcı kitap/roman/okuyacak bir şey mi istiyor, film mi istiyor, yoksa dizi mi istiyor tespit et.
    
    Eğer kullanıcı bir öneri istiyorsa (Örn: "bana aksiyon öner", "kitap tavsiye et", "ne izlesem"):
    - intent değerini "recommendation" yap.
    - content_type değerini kullanıcı kitap istiyorsa "book", dizi istiyorsa "tv", film istiyorsa veya ayırt etmediyse "movie" yap.
    - Kullanıcının belirttiği türleri (genres) küçük harfli liste olarak çıkar (Örn: ["aksiyon", "bilim kurgu"]).
    - Yıl sınırları varsa 'year_min' ve 'year_max' olarak belirt (Örn: 2010 sonrası için year_min: 2010).
    
    Eğer kullanıcı öneri istemiyor, sadece genel bir sohbet ediyorsa (Örn: "merhaba", "nasılsın", "sen kimsin"):
    - intent değerini "chat" yap.
    - content_type değerini "movie" yap.
    - 'reply_text' alanına samimi, eğlenceli, kitap ve sinemasever bir yapay zeka gibi Türkçe bir yanıt yaz.
    
    Sadece ve sadece aşağıdaki JSON formatında yanıt dön, başka hiçbir açıklama veya markdown bloğu (```json gibi) yazma:
    {{
        "intent": "recommendation",
        "content_type": "movie",
        "filters": {{
            "genres": [],
            "year_min": null,
            "year_max": null
        }},
        "reply_text": ""
    }}
    """
    try:
        # Llama 3.1 8B modelini tetikliyoruz 
        chat_completion = groq_client.chat.completions.create(
            messages=[
                {
                    "role": "user",
                    "content": prompt,
                }
            ],
            model="llama-3.1-8b-instant",
            temperature=0.1,  # JSON formatının şaşmaması için katı tutuyoruz
            max_tokens=400,
            response_format={"type": "json_object"}  # Donanımsal JSON modu zırhı buraya eklendi 
        )
        
        response_text = chat_completion.choices[0].message.content.strip()
        
        # Olası markdown işaretlemelerini temizleme zırhı
        clean_text = response_text.replace("```json", "").replace("```", "").strip()
        
        # --- BÜYÜK-KÜÇÜK HARF KORUMA ZIRHI ---
        parsed_json = json.loads(clean_text)
        if "filters" in parsed_json and "genres" in parsed_json["filters"]:
            # Model ne dönerse dönsün, boşlukları uçur ve tamamen küçük harfe sabitle
            parsed_json["filters"]["genres"] = [str(g).strip().lower() for g in parsed_json["filters"]["genres"]]

        parsed_json = normalize_ai_response(parsed_json, query)
            
        # --- DEBUG PRINT EKLE (Terminalde görmemiz için) ---
        print(f"\n[+] Groq'tan Gelen Kusursuz Filtre Yapısı: {json.dumps(parsed_json, ensure_ascii=False, indent=2)}")
        
        return parsed_json
        
    except Exception as e:
        print(f"[-] Groq sorgu analizi sırasında hata oluştu: {e}")
        return analyze_query_locally(query)

# --- 3. ANA ÖNERİ MANTIĞI ---

def get_chatbot_recommendations_logic(is_chatbot=False):
    user_id = request.args.get('userId')
    query = (request.args.get('query') or "").strip()
    raw_type = request.args.get('type')
    raw_count = request.args.get('count')
    user_data = {}
    
    if not user_id: return jsonify({"error": "userId gerekli."}), 400
    if is_chatbot and not query:
        return jsonify({
            "bot_message": "Film, dizi ya da kitap için ne tarz bir öneri istediğini yazarsan hemen seçmeye başlayabilirim.",
            "recommendations": []
        })
    if chroma_collection is None:
        return service_unavailable_response("content_vectors", "Öneri veritabanı hazır değil.")

    try:
        if users_collection is not None:
            user_doc = users_collection.document(user_id).get()
            user_data = user_doc.to_dict() if user_doc.exists else {}
        
        all_relevant_ids = list(set(extract_ids_from_entries(user_data.get('favoritesEntries', [])) + 
                                    extract_ids_from_entries(user_data.get('watchedEntries', []))))
        meta_data = get_content_from_firestore(all_relevant_ids)
        taste_vector = calculate_weighted_taste_vector(user_data, meta_data)
    except Exception as e:
        print(f"[-] Kullanıcı zevk vektörü hazırlanamadı: {e}")
        taste_vector = np.zeros(384)

    genre_filters, safe_type = [], normalize_content_type(raw_type, None) if raw_type else None
    year_min, year_max = None, None
    final_search_vector = taste_vector
    content_target = "movie"  

    if is_chatbot and query:
        ai_res = analyze_query_with_gemini(query) 
        if ai_res.get('intent') != 'recommendation':
            return jsonify({"bot_message": ai_res.get('reply_text'), "recommendations": []})
        
        content_target = normalize_content_type(ai_res.get('content_type'), 'movie')
        if not safe_type and content_target in {"movie", "tv"}:
            safe_type = content_target

        filters = ai_res.get('filters', {})
        genre_filters = expand_genre_filters(filters.get('genres', []))
        year_min, year_max = normalize_year(filters.get('year_min')), normalize_year(filters.get('year_max'))
        
        if model is not None:
            query_vector = model.encode(query)
            final_search_vector = (TASTE_VECTOR_WEIGHT * taste_vector) + (QUERY_VECTOR_WEIGHT * query_vector)

    target_count = DEFAULT_CHAT_COUNT if is_chatbot else DEFAULT_API_COUNT
    if raw_count:
        target_count = normalize_count(raw_count, target_count)
    elif is_chatbot and query:
        target_count = extract_requested_count(query, target_count)

    # --- CHATBOT KİTAP ÖNERİSİ ROUTER ---
    if is_chatbot and content_target == "book":
        if book_chroma_collection is None:
            return service_unavailable_response("book_vectors", "Kitap öneri veritabanı hazır değil.")
        try:
            book_query_results = book_chroma_collection.query(
                query_embeddings=[final_search_vector.tolist()],
                n_results=target_count * 3,  
                include=['metadatas', 'distances']
            )
            b_ids = book_query_results['ids'][0]
            b_dists = book_query_results['distances'][0]
            b_metas = book_query_results['metadatas'][0]
            
            final_books = []
            for i in range(len(b_ids)):
                cosine_sim = 1 - (b_dists[i] / 2.0)
                match_score = round((cosine_sim + 1) * 5, 2)
                
                final_books.append({
                    "book_id": b_ids[i],
                    "title": b_metas[i].get('title', 'Bilinmeyen Kitap'),
                    "authors": b_metas[i].get('authors', 'Bilinmeyen Yazar'),
                    "genre": b_metas[i].get('genre', 'Genel'),
                    "image_url": b_metas[i].get('image_url', ''),
                    "match_score": match_score,
                    "type": "book"
                })
            return jsonify({
                "bot_message": f"Senin için harika kitaplar seçtim:", 
                "recommendations": final_books[:target_count]
            })
        except Exception as e:
            print(f"[-] Kitap yönlendirmesinde hata: {e}")

    # --- FİLM / İÇERİK SORGULAMA ALANI ---
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
    backup_candidates = []  
    skipped = {"watched_or_missing_meta": 0, "type": 0, "year": 0, "genre": 0}

    for i, cid in enumerate(cand_ids):
        if cid in watched_ids or cid not in all_cand_meta:
            skipped["watched_or_missing_meta"] += 1
            continue
        cand = all_cand_meta[cid]
        
        cosine_sim = 1 - (distances[i] / 2.0)
        norm_sim = (cosine_sim + 1) * 5
        tmdb_rating = float(cand.get('rating', 0))
        final_score = round((norm_sim * 0.7) + (tmdb_rating * 0.3), 2)
        
        candidate_item = {**cand, "content_id": cid, "final_score": final_score}
        
        c_type = cand.get('type', '').lower()
        if safe_type and c_type and c_type != safe_type:
            skipped["type"] += 1
            continue
        
        try: cy = int(cand.get('year', 0))
        except: cy = 0
        if year_min and cy < year_min:
            skipped["year"] += 1
            continue
        if year_max and cy > year_max:
            skipped["year"] += 1
            continue

        if genre_filters:
            c_genres = set(normalize_genres_value(cand.get('genres', [])))
            if not c_genres.intersection(set(genre_filters)):
                skipped["genre"] += 1
                continue

        backup_candidates.append(candidate_item)
        final_candidates.append(candidate_item)

    # --- KONTENJAN DOLDURMA MANTIĞI ---
    sorted_recs = sorted(final_candidates, key=lambda x: x['final_score'], reverse=True)
    
    allow_backup_fill = not (safe_type or genre_filters or year_min or year_max)
    if allow_backup_fill and len(sorted_recs) < target_count:
        sorted_backups = sorted(backup_candidates, key=lambda x: x['final_score'], reverse=True)
        existing_ids = {x['content_id'] for x in sorted_recs}
        for b_cand in sorted_backups:
            if len(sorted_recs) >= target_count: break
            if b_cand['content_id'] not in existing_ids:
                sorted_recs.append(b_cand)
                existing_ids.add(b_cand['content_id'])

    print(
        "[debug] recommendation candidates:",
        f"chroma={len(cand_ids)}",
        f"meta={len(all_cand_meta)}",
        f"filtered={len(final_candidates)}",
        f"returned={len(sorted_recs[:target_count])}",
        f"safe_type={safe_type}",
        f"genres={genre_filters}",
        f"skipped={skipped}"
    )

    return jsonify({"bot_message": "İşte senin için seçtiklerim:", "recommendations": sorted_recs[:target_count]})

# --- 4. ENDPOINTS ---
@app.route('/api/v1/recommendations', methods=['GET'])
def get_recommendations(): return get_chatbot_recommendations_logic(is_chatbot=False)

@app.route('/api/v1/chatbot', methods=['GET'])
def get_chatbot_recommendations(): return get_chatbot_recommendations_logic(is_chatbot=True)

@app.route('/health', methods=['GET'])
def health_check():
    required_services = ["chroma", "content_vectors"]
    status_code = 200 if all(SERVICE_STATUS.get(name) for name in required_services) else 503
    return jsonify({
        "status": "ok" if status_code == 200 else "degraded",
        "services": SERVICE_STATUS,
        "errors": SERVICE_ERRORS
    }), status_code


# --- 5. TÜR BAZLI KİTAP ÖNERİ SİSTEMİ ---

book_chroma_collection = None
try:
    if client is None:
        raise RuntimeError("Chroma client hazır değil.")
    book_chroma_collection = client.get_collection(name="book_vectors")
    mark_service("book_vectors", True)
    print("[+] Kitap koleksiyonu (book_vectors) başarıyla bağlandı.")
except Exception as e:
    print(f"[-] UYARI: Kitap koleksiyonu yüklenemedi. Hata: {e}")
    mark_service("book_vectors", False, e)

@app.route('/api/v1/book-recommendations', methods=['GET'])
def get_book_recommendations():
    user_id = request.args.get('userId')
    count_param = request.args.get('count', default=15)
    if not user_id: return jsonify({"error": "userId parametresi gerekli."}), 400
    target_count = normalize_count(count_param, 15)
    if book_chroma_collection is None:
        return service_unavailable_response("book_vectors", "Kitap öneri veritabanı hazır değil.")

    try:
        if users_collection is not None:
            user_doc = users_collection.document(user_id).get()
            if not user_doc.exists: return jsonify({"status": "success", "books": []})
            user_data = user_doc.to_dict()
        else:
            user_data = {}
        watched_entries = user_data.get('watchedEntries', [])
        favorites_entries = user_data.get('favoritesEntries', [])

        loved_movie_ids = []
        for entry in favorites_entries: loved_movie_ids.append(str(entry.get('id')) if isinstance(entry, dict) else str(entry))
        for entry in watched_entries:
            if isinstance(entry, dict) and float(entry.get('rating', 0)) >= 7: loved_movie_ids.append(str(entry.get('id')))

        if not loved_movie_ids:
            results = book_chroma_collection.get(limit=target_count, include=['metadatas'])
            books = []
            for i in range(len(results['ids'])):
                books.append({
                    "book_id": results['ids'][i], "title": results['metadatas'][i].get('title', 'Kült Kitap'),
                    "authors": results['metadatas'][i].get('authors', 'Bilinmeyen Yazar'),
                    "genre": results['metadatas'][i].get('genre', 'Genel'),
                    "image_url": results['metadatas'][i].get('image_url', ''), "match_score": 7.5
                })
            return jsonify({"status": "success", "books": books})

        movie_meta = get_content_from_firestore(loved_movie_ids)
        user_favorite_genres = []
        for mid in loved_movie_ids:
            if mid in movie_meta: user_favorite_genres.extend([g.lower() for g in movie_meta[mid].get('genres', [])])

        if not user_favorite_genres: user_favorite_genres = ["fiction"]
        most_common_genre = max(set(user_favorite_genres), key=user_favorite_genres.count)
        mapped_genre = GENRE_MAP.get(most_common_genre, most_common_genre)

        if model is None:
            return service_unavailable_response("sentence_model", "Kitap önerisi için metin modeli hazır değil.")
        query_vector = model.encode(mapped_genre).tolist()
        query_results = book_chroma_collection.query(query_embeddings=[query_vector], n_results=target_count, include=['metadatas', 'distances'])
        
        cand_ids, distances, metadatas = query_results['ids'][0], query_results['distances'][0], query_results['metadatas'][0]
        final_books = []
        for i in range(len(cand_ids)):
            cosine_sim = 1 - (distances[i] / 2.0)
            final_books.append({
                "book_id": cand_ids[i], "title": metadatas[i].get('title', 'Bilinmeyen Kitap'),
                "authors": metadatas[i].get('authors', 'Bilinmeyen Yazar'), "genre": metadatas[i].get('genre', 'Genel'),
                "published_year": metadatas[i].get('published_year', 'N/A'), "image_url": metadatas[i].get('image_url', ''),
                "match_score": round((cosine_sim + 1) * 5, 2)
            })
        return jsonify({"status": "success", "matched_genre": mapped_genre, "books": final_books})
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    port = int(os.getenv("PORT", 5000))
    debug = parse_bool_env("FLASK_DEBUG", False)
    app.run(host='0.0.0.0', port=port, debug=debug)
