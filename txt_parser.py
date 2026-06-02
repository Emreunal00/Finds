import pandas as pd
import os
import glob
import re

def parse_text_files():
    all_data = []
    # userdata klasöründeki tüm .txt dosyalarına bak
    txt_files = glob.glob(os.path.join("userdata", "*.txt"))
    
    if not txt_files:
        print("[!] 'userdata' klasöründe .txt dosyası bulunamadı!")
        return pd.DataFrame()

    for file_path in txt_files:
        username = os.path.basename(file_path).replace(".txt", "")
        print(f">>> {username} işleniyor...")
        
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Regex ile "Poster for [Film Adı] ([Yıl])" ve altındaki yıldızları yakala
        # Pattern: Film Adı (Yıl) \n Yıldızlar
        pattern = r"Poster for (.*?) \((\d{4})\)\n([★½]+)"
        matches = re.findall(pattern, content)
        
        for match in matches:
            title = match[0]
            year = match[1]
            rating_str = match[2]
            
            # Yıldızları puana çevir
            stars = rating_str.count('★') + (0.5 if '½' in rating_str else 0)
            
            all_data.append({
                'username': username,
                'title': f"{title}", # Vektör DB'de eşleşme için yıl kalsın veya silinebilir
                'user_rating': stars * 2, # 10 üzerinden
                'year': year
            })
            
    return pd.DataFrame(all_data)

if __name__ == "__main__":
    if not os.path.exists("userdata"):
        os.makedirs("userdata")
        
    df = parse_text_files()
    
    if not df.empty:
        df.to_csv("multi_user_ratings.csv", index=False)
        print(f"\n[BAŞARILI] Toplam {len(df)} oylama kaydedildi.")
    else:
        print("\n[HATA] Eşleşme bulunamadı. Metin formatını kontrol et.")