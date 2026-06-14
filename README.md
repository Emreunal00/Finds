# Finds

Umut Emre Ünal and Eren Ergani's final project for Istanbul Bilgi University

Finds is an iOS application that learns from a user's viewing and reading
history to recommend movies, TV shows, and books. The SwiftUI client stores user
and profile data with Firebase, retrieves content from TMDB and Google Books,
and receives personalized recommendations from a Flask API.

## Features

- Sign up and sign in with email and password
- Use multiple profiles under the same account
- Search for movies, TV shows, and books
- Manage a watchlist, watched items, favorites, and custom lists
- Rate content and view community ratings
- Receive personalized recommendations based on user interactions
- Ask for movie, TV show, and book recommendations using natural language
- Use a mini-game to help choose content
- Select light, dark, or system appearance

## Architecture

```text
Finds/
├── app.py                     # Flask recommendation API
├── chroma_db/                 # Persistent ChromaDB vector database
├── data_loader.py             # Rebuilds the TMDB content pool
├── book_loader.py             # Adds Google Books content to ChromaDB
├── db_updater_2026.py         # Adds current TMDB movies to the vector pool
├── evaluation.py              # Evaluates recommendation MAE
├── requirements.txt           # Backend dependencies
└── FindsApp/
    ├── FindsApp.xcodeproj     # Xcode project
    ├── FindsApp/              # SwiftUI application sources
    ├── FindsAppTests/         # Unit tests
    └── FindsAppUITests/       # UI tests
```

The recommendation system stores embeddings generated with the
`all-MiniLM-L6-v2` sentence-transformer model in ChromaDB. It calculates a user
taste vector by weighting favorites and rated content. For chatbot requests,
this vector is combined with the user's natural-language query. If a Groq API
key is not configured, the API continues to work using local query analysis.

## Requirements

### Backend

- Python 3.10 or later
- A Firebase project and Firebase Admin service-account JSON file
- The included `chroma_db/` directory, or API keys to rebuild the content pool
- Optional: a Groq API key

### iOS Application

- macOS and Xcode
- A Firebase project with Firebase Authentication and Cloud Firestore enabled
- A Firebase `GoogleService-Info.plist` file for your iOS application
- A Google Books API key

## Backend Setup

1. Open the project directory and create a virtual environment:

   ```bash
   cd Finds
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

2. Create a `.env` file in the project root:

   ```dotenv
   FIREBASE_KEY_PATH=./firebase-admin-key.json
   GROQ_API_KEY=your_groq_api_key
   GOOGLE_BOOKS_API_KEY=your_google_books_api_key
   TMDB_API_KEY=your_tmdb_api_key
   PORT=5000
   FLASK_DEBUG=false
   ```

   `FIREBASE_KEY_PATH` is required. `GROQ_API_KEY` is optional. The Google Books
   and TMDB keys are only required when running the related data-loader scripts.

3. Place the Firebase Admin service-account file at the path configured in
   `.env`. Do not commit this file.

4. Start the API:

   ```bash
   python app.py
   ```

5. Check the service status:

   ```bash
   curl http://localhost:5000/health
   ```

`/health` returns `503` if the core recommendation pool is unavailable and
`200` when it is ready.

## Run with Docker

```bash
docker build -t finds-api -f dockerfile .
docker run --rm -p 8080:8080 \
  --env-file .env \
  -v "$PWD/firebase-admin-key.json:/app/firebase-admin-key.json:ro" \
  finds-api
```

The Docker image serves the API on port `8080` using Gunicorn. The `chroma_db/`
directory is copied into the image.

## iOS Application Setup

1. Create an iOS application in Firebase Console.
2. Enable the email/password provider in Firebase Authentication.
3. Create a Cloud Firestore database.
4. Add the Firebase `GoogleService-Info.plist` file to `FindsApp/FindsApp/`.
5. Copy `FindsApp/FindsApp/Secrets.example.plist` to `Secrets.plist` and add
   your Google Books API key.
6. To use a local backend, update `baseURL` in
   `FindsApp/FindsApp/FindsAPI.swift` with an address reachable from your
   development device.
7. Open `FindsApp/FindsApp.xcodeproj` in Xcode. After the Firebase dependencies
   are resolved, run the application.

Example address when connecting to a local API from the simulator:

```swift
static let baseURL = URL(string: "http://127.0.0.1:5000")!
```

When using a physical device, replace `127.0.0.1` with your Mac's local network
IP address.

## API Endpoints

| Method | Endpoint | Description |
| --- | --- | --- |
| `GET` | `/health` | Returns the status of backend services |
| `GET` | `/api/v1/recommendations` | Returns profile-based movie or TV recommendations |
| `GET` | `/api/v1/chatbot` | Generates recommendations or a chat reply from a natural-language query |
| `GET` | `/api/v1/book-recommendations` | Returns profile-based book recommendations |

Example requests:

```bash
curl "http://localhost:5000/api/v1/recommendations?userId=USER_ID&profileId=PROFILE_ID&type=movie&count=10"

curl --get "http://localhost:5000/api/v1/chatbot" \
  --data-urlencode "userId=USER_ID" \
  --data-urlencode "profileId=PROFILE_ID" \
  --data-urlencode "query=recommend science fiction movies released after 2010"

curl "http://localhost:5000/api/v1/book-recommendations?userId=USER_ID&profileId=PROFILE_ID&count=10"
```

## Rebuild the Content Pool

The included `chroma_db/` directory can be used to run the API. To rebuild or
extend the content pool, install the additional script dependencies:

```bash
pip install requests tmdbv3api
```

To retrieve movie and TV data from TMDB and rebuild the `content_vectors`
collection:

```bash
python data_loader.py
```

To add Google Books data to the existing `book_vectors` collection:

```bash
python book_loader.py
```

To add current movie records to the existing content pool:

```bash
python db_updater_2026.py
```

`data_loader.py` deletes and rebuilds the existing `content_vectors`
collection. Back up the database before running it.

## Evaluation

To evaluate the weighted-vector recommendation approach using the MAE metric,
provide `tmdb_content_10k.json`, `multi_user_ratings.csv`, and the additional
analysis dependencies:

```bash
pip install pandas matplotlib seaborn
python evaluation.py
```

The output chart is generated as `evaluation_report_v2.png`.

## Tests

Run the iOS unit and UI tests from Xcode or the command line:

```bash
cd FindsApp
xcodebuild test \
  -project FindsApp.xcodeproj \
  -scheme FindsApp \
  -testPlan FindsApp \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The simulator name may differ depending on your local Xcode installation.

## Security Notes

- Do not commit `.env`, the Firebase Admin service account, or `Secrets.plist`.
- Do not keep API keys in source code. Restrict keys used by the mobile client
  to the required application and API scopes in the relevant provider console.
- Rotate keys that have previously appeared in source code or Git history.

## License

No license file has been added to this repository yet.
