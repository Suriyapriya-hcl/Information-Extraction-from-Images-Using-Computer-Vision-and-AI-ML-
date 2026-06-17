from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
import shutil
import uuid
import os

from main_script import extract_text_from_image, DocumentChat

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

sessions = {}

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.post("/upload/")
async def upload(file: UploadFile = File(...)):
    file_id = str(uuid.uuid4())
    file_path = os.path.join(UPLOAD_DIR, file_id + ".png")

    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    data = extract_text_from_image(file_path)

    sessions[file_id] = {
        "data": data if data else {},
        "chat": DocumentChat(data if data else {})
    }

    return {
        "id": file_id,
        "analysis": data if data else {}
    }


@app.post("/ask/")
async def ask(id: str = Form(...), question: str = Form(...)):
    session = sessions.get(id)

    if not session:
        return {"answer": "Session expired or invalid ID"}

    chat = session["chat"]
    answer = chat.ask(question)

    return {"answer": answer}

@app.post("/ask/")
async def ask(id: str = Form(...), question: str = Form(...)):
    context = sessions.get(id)

    if not context:
        return {"answer": "Session expired or invalid ID"}

    chat = DocumentChat(context)
    answer = chat.ask(question)

    return {"answer": answer}
