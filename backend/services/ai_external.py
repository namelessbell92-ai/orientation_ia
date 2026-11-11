from transformers import pipeline

# Modèle gratuit de classification de texte
classifier = pipeline("text-classification", model="distilbert-base-uncased-finetuned-sst-2-english")

def orientation_ai(prompt):
    result = classifier(prompt)[0]
    return f"{result['label']} (score: {result['score']:.2f})"
