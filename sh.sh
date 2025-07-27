#!/bin/bash

echo "🦐 Setup Web Deteksi Udang dengan systemd"

# Konfigurasi pengguna dan path (ubah jika perlu)
APP_USER=$USER
APP_DIR="/home/$APP_USER/shrimp_counter_web"

# 1. Install dependensi
echo "📦 Menginstal dependensi Python..."
sudo apt update
sudo apt install -y python3 python3-pip
pip3 install flask tensorflow pillow

# 2. Buat struktur proyek
echo "📁 Membuat direktori proyek di $APP_DIR"
mkdir -p "$APP_DIR/static"

# 3. Salin model (pastikan file ada di folder ini)
echo "📂 Menyalin model best_float32.tflite..."
cp best_float32.tflite "$APP_DIR/"

# 4. Buat file app.py
cat > "$APP_DIR/app.py" << 'EOF'
from flask import Flask, request, jsonify, render_template
import numpy as np
import tensorflow as tf
from PIL import Image

interpreter = tf.lite.Interpreter(model_path="best_float32.tflite")
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

app = Flask(__name__, static_folder='static', template_folder='static')

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/predict', methods=['POST'])
def predict():
    try:
        if 'image' not in request.files:
            return jsonify({'error': 'No image uploaded'}), 400

        file = request.files['image']
        image = Image.open(file.stream).convert('RGB')
        image = image.resize((224, 224))
        input_array = np.array(image, dtype=np.float32) / 255.0
        input_array = np.expand_dims(input_array, axis=0)

        interpreter.set_tensor(input_details[0]['index'], input_array)
        interpreter.invoke()
        output_data = interpreter.get_tensor(output_details[0]['index'])

        jumlah_udang = int(np.round(output_data[0][0]))
        return jsonify({'jumlah_udang': jumlah_udang})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

# 5. Buat HTML form
cat > "$APP_DIR/static/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>Deteksi Udang</title>
</head>
<body>
  <h1>Upload Gambar Udang</h1>
  <form id="upload-form" enctype="multipart/form-data">
    <input type="file" name="image" accept="image/*" required />
    <button type="submit">Upload</button>
  </form>
  <h2>Hasil:</h2>
  <pre id="result"></pre>

  <script>
    const form = document.getElementById('upload-form');
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const formData = new FormData(form);

      const response = await fetch('/predict', {
        method: 'POST',
        body: formData
      });

      const result = await response.json();
      document.getElementById('result').textContent =
        result.jumlah_udang !== undefined
        ? `Jumlah Udang: ${result.jumlah_udang}`
        : `Error: ${result.error}`;
    });
  </script>
</body>
</html>
EOF

# 6. Buat systemd service
SERVICE_FILE="/etc/systemd/system/shrimp_counter.service"
echo "⚙️ Membuat systemd service di $SERVICE_FILE"
sudo bash -c "cat > $SERVICE_FILE" << EOF
[Unit]
Description=Shrimp Counter Web Server
After=network.target

[Service]
User=$APP_USER
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/python3 app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 7. Reload systemd dan aktifkan service
echo "🔁 Mengaktifkan service..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable shrimp_counter
sudo systemctl restart shrimp_counter

echo "✅ Web server udang berjalan di background."
echo "🌐 Akses di: http://$(hostname -I | awk '{print $1}'):5000/"
