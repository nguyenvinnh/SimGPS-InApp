# SimGPS-InApp 📍🛰️

Dự án iOS Tweak giả mạo vị trí GPS (Fake Location) trực tiếp trong ứng dụng iOS thông qua thư viện dylib.



##  Chức Năng

* **Thay đổi tọa độ tùy chỉnh:** Thay đổi vị trí GPS hiện tại của ứng dụng thành bất kỳ tọa độ nào mong muốn (Vĩ độ / Kinh độ).
* Mô phỏng lộ trình (Route Simulation): Mô phỏng chuyển động dựa vào file gpx, người dùng có thể tuỳ chỉnh tốc độ tối đa của mô phỏng 
* **Định vị liên tục:** Tự động duy trì và phát tọa độ giả lập liên tục (tương thích tốt với các dịch vụ bản đồ như Google Maps, Apple Maps, v.v.).

##  Kỹ Thuật Giả Mạo Vị Trí

Dự án sử dụng **Logos (Substrate / ElleKit)** để can thiệp vào tầng `CoreLocation Framework` của iOS:

1. **Hook `CLLocationManager**`:
* Ghi đè phương thức `- (CLLocation *)location` để trả về đối tượng `CLLocation` mang tọa độ giả lập.
* Bắt các hàm khởi tạo định vị: `-startUpdatingLocation` và `-requestLocation`.


2. **Theo dõi Instance & Đẩy vị trí liên tục (Continuous Delivery Loop)**:
* Lưu trữ các đối tượng `CLLocationManager` đang hoạt động vào `NSHashTable` (weak reference).
* Chạy `NSTimer` chu kỳ 1 giây để chủ động gửi tọa độ mới qua delegate `-locationManager:didUpdateLocations:`, vượt qua cơ chế cache vị trí thực của app.




##  Mục Đích Nghiên Cứu & Học Tập

* Dự án này được tạo ra **chỉ nhằm mục đích nghiên cứu bảo mật, học tập cách hoạt động của Objective-C Runtime, cơ chế Hooking trong iOS (Theos/Logos)** và tìm hiểu cách các ứng dụng xử lý dữ liệu định vị (Location Services).
* Không khuyến khích hoặc cổ suyến việc sử dụng tweak này để gian lận, lừa đảo, hoặc vi phạm điều khoản sử dụng của bất kỳ bên thứ ba nào.

## 📜 Điều Khoản Sử Dụng Mã Nguồn (License & Usage)
* Chia sẻ miễn phí: Mã nguồn của dự án này được chia sẻ hoàn toàn miễn phí phục vụ mục đích học tập và nghiên cứu cá nhân.

* Yêu cầu xin phép: Nếu bạn có ý định sử dụng, tích hợp hoặc tham khảo một phần hay toàn bộ mã nguồn này vào bất kỳ dự án nào khác (bao gồm cả dự án thương mại/có lợi nhuận lẫn phi lợi nhuận), bạn bắt buộc phải có sự đồng ý/cho phép bằng văn bản từ tác giả trước khi thực hiện.

##  Tuyên Bố Trách Nhiệm 

* **Tự chịu trách nhiệm:** Người sử dụng tự chịu hoàn toàn mọi rủi ro, trách nhiệm pháp lý hoặc các hình thức xử phạt (như khóa tài khoản tạm thời/vĩnh viễn) từ nhà phát hành ứng dụng mục tiêu khi quyết định sử dụng dự án này.
* **Không bảo đảm:** Tác giả không chịu bất kỳ trách nhiệm nào đối với bất kỳ thiệt hại trực tiếp hoặc gián tiếp nào phát sinh từ việc sử dụng, triển khai hoặc lạm dụng mã nguồn từ dự án này.
