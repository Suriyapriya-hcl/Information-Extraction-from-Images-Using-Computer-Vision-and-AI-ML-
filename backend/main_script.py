import cv2
import numpy as np
import os
from ultralytics import YOLO
from paddleocr import PaddleOCR
import google.generativeai as genai
from realesrgan import RealESRGANer
from basicsr.archs.rrdbnet_arch import RRDBNet

def load_esrgan():
    model = RRDBNet(
        num_in_ch=3,
        num_out_ch=3,
        num_feat=64,
        num_block=23,
        num_grow_ch=32,
        scale=4
    )

    upsampler = RealESRGANer(
        scale=4,
        model_path=r"C:\Users\suriyapriya.je\Downloads\poc\models\RealESRGAN_x4plus.pth",
        model=model,
        tile=200,
        tile_pad=10,
        pre_pad=0,
        half=False
    )
    return upsampler

print("Loading ESRGAN...")
esrgan = load_esrgan()
def enhance_image_esrgan(img):
    try:
        output, _ = esrgan.enhance(img, outscale=4)
        return output
    except Exception as e:
        print("ESRGAN failed:", e)
        return img  

YOLO_WEIGHTS = r"C:\Users\suriyapriya.je\Downloads\poc\weights\best.pt"
DET_MODEL_DIR = r"C:\Users\suriyapriya.je\Downloads\paddle_models\en_PP-OCRv3_det_infer"
REC_MODEL_DIR = r"C:\Users\suriyapriya.je\Downloads\paddle_models\en_PP-OCRv3_rec_infer"

GEMINI_API_KEY = ""  

yolo_model = YOLO(YOLO_WEIGHTS)

ocr = PaddleOCR(
    lang="en",
    use_angle_cls=True,
    det_model_dir=DET_MODEL_DIR,
    rec_model_dir=REC_MODEL_DIR,
    show_log=False
)

genai.configure(api_key=GEMINI_API_KEY)

llm = genai.GenerativeModel(
    "gemini-2.5-flash",
    generation_config={"temperature": 0}
)

def preprocess_image(img):
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    h, w = gray.shape
    if w < 1200:
        scale = 1200 / w
        gray = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)

    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (25, 25))
    bg = cv2.morphologyEx(gray, cv2.MORPH_CLOSE, kernel)
    gray = cv2.divide(gray, bg, scale=255)

    gray = cv2.fastNlMeansDenoising(gray, h=10)

    if np.std(gray / 255.0) < 0.20:
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
        gray = clahe.apply(gray)

    return gray


def group_into_lines(ocr_result, y_threshold=15):
    items = []

    for box, (text, _) in ocr_result:
        xs = [p[0] for p in box]
        ys = [p[1] for p in box]

        items.append({
            "text": text,
            "x": min(xs),
            "y": sum(ys) / len(ys)
        })

    items.sort(key=lambda x: x["y"])

    lines = []
    for item in items:
        for line in lines:
            if abs(line[0]["y"] - item["y"]) < y_threshold:
                line.append(item)
                break
        else:
            lines.append([item])

    final_lines = []

    for line in lines:
        line.sort(key=lambda x: x["x"])
        final_lines.append(" ".join(i["text"] for i in line))

    return final_lines



def extract_text_from_image(image_path):
    img = cv2.imread(image_path)

    if img is None:
        return ""

    results = yolo_model(img, conf=0.5)[0]

    if results.boxes is None or len(results.boxes) == 0:
        return ""

    boxes = results.boxes.xyxy.cpu().numpy()

    text_blocks = []

    for (x1, y1, x2, y2) in boxes:
        x1, y1, x2, y2 = map(int, (x1, y1, x2, y2))

        crop = img[y1:y2, x1:x2]

        if crop.size == 0:
            continue
     
        enhanced_crop = enhance_image_esrgan(crop)


        processed_crop = preprocess_image(enhanced_crop)

        ocr_result = ocr.ocr(processed_crop, cls=True)
        print(ocr_result)
        if ocr_result and ocr_result[0]:
            lines = group_into_lines(ocr_result[0])
            text_blocks.append("\n".join(lines))

    return "\n\n".join(text_blocks)

def analyze_text(ocr_text):
    ocr_text = ocr_text.replace("|", " : ")

    prompt = f"""
You are a strict information extraction system.
Rules:
- Clean OCR Errors
- Extract all fields  
- Detect compound fields and split them correctly:
   Examples:
   - p/t → Pressure / Temperature
   - Q/H → Flow Rate / Head
- DO NOT guess or add missing values 
- If missing, return: Not mentioned
- Remove Certification fields
- Standardise Units 

Return ONLY valid JSON like:
{{
  "Field Name": "Value",
  "Field Name": "Value"
}}


OCR Text:
{ocr_text}
"""

    response = llm.generate_content(prompt)
    result = response.text.strip()

    # Remove markdown if present
    if result.startswith("```"):
        result = result.replace("```json", "").replace("```", "").strip()
    import json

    try:
        data = json.loads(result)
        return json.dumps(data, indent=2)

    except Exception as e:
        print("JSON parsing error:", e)
        return result

class DocumentChat:
    def __init__(self, context):
        self.context = context

    def ask(self, question):
        prompt = f"""
You are a document QA system.


Rules:
- Answer using ONLY the given context
- Extract exact values from the text
- If answer is not present, reply: I cannot provide ,since it is not present in the image.

Context:
{self.context}

Question:
{question}
"""

        response = llm.generate_content(prompt)
        answer = response.text if response.text else "No answer found"

        self.context += f"\nQ: {question}\nA: {answer}"

        return answer
