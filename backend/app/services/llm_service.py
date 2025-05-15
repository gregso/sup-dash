import os
import json
import requests
from typing import Optional, Dict, Any

from app.config import settings

class LLMService:
    def __init__(self):
        self.provider = settings.LLM_PROVIDER.lower()
        self.enabled = settings.LLM_ENABLED
        
        # Ollama configuration
        if self.provider == 'ollama':
            self.ollama_base_url = settings.OLLAMA_BASE_URL
            self.ollama_model = settings.OLLAMA_MODEL
        
        # OpenAI configuration (as fallback)
        elif self.provider == 'openai':
            self.openai_api_key = settings.OPENAI_API_KEY
            self.openai_model = settings.OPENAI_MODEL
            
            if self.openai_api_key:
                import openai
                openai.api_key = self.openai_api_key
        
    def summarize_task(self, task_content: str) -> Optional[str]:
        """Generate a summary of task content using the configured LLM provider"""
        if not self.enabled or not task_content:
            return None
            
        if self.provider == 'ollama':
            return self._summarize_with_ollama(task_content)
        elif self.provider == 'openai':
            return self._summarize_with_openai(task_content)
        else:
            print(f"Unsupported LLM provider: {self.provider}")
            return None

    def _summarize_with_ollama(self, task_content: str) -> Optional[str]:
        """Generate a summary using Ollama local LLM"""
        try:
            prompt = f"""
            Please provide a concise summary (maximum 2 sentences) of the following task content:
            
            {task_content}
            
            Focus on the key details and action items only.
            """
            
            # Make request to Ollama API
            response = requests.post(
                f"{self.ollama_base_url}/api/generate",
                json={
                    "model": self.ollama_model,
                    "prompt": prompt,
                    "system": "You are a helpful assistant that summarizes task content concisely.",
                    "stream": False,
                    "options": {
                        "temperature": 0.3,
                        "num_predict": 100  # Limit output tokens
                    }
                }
            )
            
            if response.status_code == 200:
                result = response.json()
                summary = result.get('response', '').strip()
                return summary
            else:
                print(f"Error from Ollama: {response.text}")
                return None
                
        except Exception as e:
            print(f"Error generating summary with Ollama: {e}")
            return None

    def _summarize_with_openai(self, task_content: str) -> Optional[str]:
        """Generate a summary using OpenAI API (fallback)"""
        if not self.openai_api_key:
            return None
            
        try:
            import openai
            
            prompt = f"""
            Please provide a concise summary (maximum 2 sentences) of the following task content:
            
            {task_content}
            
            Focus on the key details and action items only.
            """
            
            response = openai.ChatCompletion.create(
                model=self.openai_model,
                messages=[
                    {"role": "system", "content": "You are a helpful assistant that summarizes task content concisely."},
                    {"role": "user", "content": prompt}
                ],
                max_tokens=100,
                temperature=0.3
            )
            
            summary = response.choices[0].message.content.strip()
            return summary
            
        except Exception as e:
            print(f"Error generating summary with OpenAI: {e}")
            return None

    def generate_embeddings(self, text: str) -> Optional[list]:
        """Generate embeddings for semantic search"""
        if not self.enabled or not text:
            return None
            
        if self.provider == 'ollama':
            return self._generate_embeddings_with_ollama(text)
        elif self.provider == 'openai':
            return self._generate_embeddings_with_openai(text)
        else:
            return None

    def _generate_embeddings_with_ollama(self, text: str) -> Optional[list]:
        """Generate embeddings using Ollama"""
        try:
            response = requests.post(
                f"{self.ollama_base_url}/api/embeddings",
                json={
                    "model": self.ollama_model,
                    "prompt": text
                }
            )
            
            if response.status_code == 200:
                result = response.json()
                return result.get('embedding')
            else:
                print(f"Error from Ollama: {response.text}")
                return None
                
        except Exception as e:
            print(f"Error generating embeddings with Ollama: {e}")
            return None

    def _generate_embeddings_with_openai(self, text: str) -> Optional[list]:
        """Generate embeddings using OpenAI API (fallback)"""
        if not self.openai_api_key:
            return None
            
        try:
            import openai
            
            response = openai.Embedding.create(
                model="text-embedding-ada-002",
                input=text
            )
            
            return response['data'][0]['embedding']
            
        except Exception as e:
            print(f"Error generating embeddings with OpenAI: {e}")
            return None

    def semantic_search(self, query: str, contents: list) -> list:
        """Search task contents using semantic similarity"""
        query_embedding = self.generate_embeddings(query)
        if not query_embedding:
            return []
            
        results = []
        for content in contents:
            content_embedding = self.generate_embeddings(content['text'])
            if content_embedding:
                similarity = self.cosine_similarity(query_embedding, content_embedding)
                results.append({
                    'task_id': content['task_id'],
                    'similarity': similarity,
                    'text': content['text']
                })
        
        # Sort by similarity (highest first)
        results.sort(key=lambda x: x['similarity'], reverse=True)
        return results[:5]  # Return top 5 results

    def cosine_similarity(self, a, b):
        """Calculate cosine similarity between two vectors"""
        import numpy as np
        return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))
