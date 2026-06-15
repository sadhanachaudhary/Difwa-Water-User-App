# Difwa Water App

A comprehensive Flutter application for water delivery and related services, designed with a seamless user experience, digital wallet integration, and real-time tracking.

## 🚀 Features

- **User Authentication**: Secure login and registration using Firebase Authentication.
- **Water & Restaurant Delivery**: Browse available water delivery services and restaurants.
- **Real-time Tracking**: Live order tracking using Google Maps and Geolocator.
- **Digital Wallet**: In-app wallet management for quick and seamless payments.
- **Secure Payments**: Integrated with Razorpay for secure transactions.
- **Shopping Cart**: Intuitive cart management and checkout process.
- **Push Notifications**: Real-time updates via Firebase Cloud Messaging and local notifications.
- **Live Communication**: Socket.io integration for instant updates and chat features.
- **PDF Generation**: Generate and print invoices or receipts directly from the app.

## 🛠️ Tech Stack & Libraries

- **Framework**: Flutter (`sdk: flutter`)
- **State Management**: Riverpod (`flutter_riverpod`) & Provider
- **Networking**: Dio (`dio`, `pretty_dio_logger`) & HTTP
- **Maps & Location**: `google_maps_flutter`, `geolocator`, `geocoding`
- **Real-time & Background**: `socket_io_client`, `flutter_foreground_task`
- **Backend & Cloud**: Firebase (`firebase_core`, `firebase_messaging`)
- **Payments**: Razorpay (`razorpay_flutter`)
- **Local Storage**: `shared_preferences`, `flutter_secure_storage`
- **UI & Animations**: `flutter_animate`, `lottie` (assets), `confetti`, `carousel_slider`, `google_fonts`
- **Utilities**: `flutter_dotenv` (Environment variables), `pdf` & `printing`

## 📦 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Version >=3.0.0 <4.0.0)
- Android Studio / VS Code
- Xcode (for iOS development)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository_url>
   cd difwa_continue_flutter_app
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Environment Setup**
   Copy the example environment file and configure your keys:
   ```bash
   cp .env.example .env
   ```
   *(Make sure to add your API keys, Razorpay credentials, and Google Maps API keys to the `.env` file.)*

4. **Run the App**
   ```bash
   flutter run
   ```

## 📁 Project Structure

* `lib/app/modules/home/`: Contains main dashboard, restaurant/water lists, and cart summary.
* `lib/app/modules/wallet/`: Digital wallet management and transaction history.
* `lib/app/data/services/`: Core services including `auth_service`, `rider_service`, etc.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!
Feel free to check the [issues page](#) if you want to contribute.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
