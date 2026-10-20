# Roblox TikTok LIVE Dance — starter project

Bộ khung gồm:
- `app.py`: máy chủ Flask + client TikTokLive + hàng đợi lệnh.
- `roblox/TikTokDanceController.server.lua`: Script phía server Roblox, tự dựng sân khấu đơn giản, đọc hàng đợi Render, tạo avatar Roblox và cho nhảy.
- `requirements.txt`, `render.yaml`: cấu hình triển khai Render.

> Đây là bộ khởi đầu cần bạn tự kết nối tài khoản và triển khai. Không thể bảo đảm TikTokLive kết nối được mọi tài khoản/LIVE; TikTok có thể thay đổi giao thức hoặc giới hạn truy cập.

## 1. Chuẩn bị GitHub

1. Tạo một repository mới, ví dụ `roblox-tiktok-live`.
2. Tải các file trong ZIP này lên thư mục gốc, giữ nguyên cấu trúc.
3. Commit các thay đổi.

## 2. Tạo dịch vụ Render

1. Render Dashboard → New → Web Service.
2. Chọn repository vừa tạo.
3. Build Command: `pip install -r requirements.txt`
4. Start Command: `gunicorn app:app --workers 1 --threads 4 --timeout 120`
5. Thêm Environment Variables:
   - `TIKTOK_USERNAME`: username tài khoản đang phát LIVE (có thể có hoặc không có `@`).
   - `BRIDGE_KEY`: chuỗi bí mật dài, ngẫu nhiên. Tạo riêng cho bạn, không dùng ví dụ công khai.
6. Deploy. Không đăng BRIDGE_KEY lên GitHub hoặc gửi cho người khác.

Khi Render Live, mở `https://TEN-DICH-VU.onrender.com/health`. Bạn sẽ thấy trạng thái JSON. `tiktok_state` cần chuyển sang `connected` khi client kết nối được. Nếu là `error` hoặc `disconnected`, xem Render Logs để biết lý do. Nếu `connecting` mãi, kết nối TikTok chưa hoàn tất.

## 3. Cài Script vào Roblox Studio

1. Mở Roblox Studio và game/experience của bạn.
2. Trong Explorer, mở `ServerScriptService`.
3. Tạo một `Script` (không phải LocalScript), đặt tên `TikTokDanceController`.
4. Dán nội dung file `roblox/TikTokDanceController.server.lua`.
5. Trong `ServerStorage`, tạo `StringValue` tên chính xác `BridgeKey`.
6. Đặt `BridgeKey.Value` bằng đúng giá trị `BRIDGE_KEY` trong Render. Không chia sẻ giá trị này.
7. Trong script Roblox, thay `https://YOUR-RENDER-SERVICE.onrender.com/next` bằng URL dịch vụ Render thật của bạn, thêm `/next`.
8. Roblox Studio → File → Experience Settings → Security → bật **Allow HTTP Requests**.
9. Nhấn Play để thử. Xem View → Output, chọn ngữ cảnh Server để xem log.

## 4. Thử trên LIVE

1. Mở TikTok LIVE Studio và bắt đầu phát trực tiếp.
2. Dùng một tài khoản khác gửi bình luận `!join Roblox` (thay `Roblox` bằng username Roblox hợp lệ).
3. Render Logs cần hiện `TIKTOK_COMMENT` rồi `AVATAR_QUEUED`.
4. Roblox Server Output cần hiện `Creating avatar for ...` rồi `Dancing: ...`.

## 5. Chẩn đoán nhanh

- `tiktok_state=connecting`: xem log khởi động; client chưa xác nhận kết nối.
- `tiktok_state=error`: đọc `last_error` ở `/health` và Render Logs. Không chia sẻ secrets.
- Có `TIKTOK_CONNECTED` nhưng không có `TIKTOK_COMMENT`: client kết nối nhưng chưa nhận bình luận; xác nhận đúng username đang LIVE và LIVE công khai/đang hoạt động.
- Có `AVATAR_QUEUED` nhưng avatar không xuất hiện: kiểm tra Roblox Output, URL Render, `BridgeKey`, Allow HTTP Requests.
- `{"username":null}` từ `/next` là bình thường khi hàng đợi trống.
- Dịch vụ Render free có thể ngủ khi không hoạt động, làm request đầu chậm.

## 6. An toàn

- Không đưa `BRIDGE_KEY` vào LocalScript, chat công khai, ảnh chụp hoặc GitHub.
- Chỉ dùng trong experience bạn quản lý.
- TikTokLive là thư viện bên thứ ba, không phải API chính thức của TikTok; kết nối có thể thay đổi hoặc ngừng hoạt động.
