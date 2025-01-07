import SwiftUI
import WatchConnectivity

class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - WCSessionDelegate Methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Handle session activation
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Handle session inactivity
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Handle session deactivation
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Handle receiving data from Watch
        NotificationCenter.default.post(name: Notification.Name("didReceiveMessage"), object: message)
    }
}

struct ContentView: View {
    @State private var temperature: Double?
    @State private var heartRate: Double?
    @State private var heartRates: [Double] = []
    @State private var hrv: Double?
    @State private var steps: Double?
    @State private var anomalyDetails: (isAnomaly: Bool, score: Double)?
    @State private var errorMessage: String?
    let healthKitManager = HealthKitManager()
    let homeKitManager = HomeKitManager()
    let watchConnectivity = WatchConnectivityManager.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerView
                    healthDataView
                    anomalyView
                    heartRatesView
                    refreshButton
                    demoButton
                    homeKitNavigationLink
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .onAppear {
                requestHealthKitAuthorization()
                setupNotificationObserver()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var headerView: some View {
        Text("Health Data Monitor")
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .padding(.top)
    }

    private var healthDataView: some View {
        VStack(spacing: 15) {
            dataCard(title: "Body Temperature", value: temperature.map { "\($0)°C" } ?? "--", icon: "thermometer")
            dataCard(title: "Heart Rate", value: heartRate.map { "\(Int($0)) BPM" } ?? "--", icon: "heart.fill")
            dataCard(title: "Heart Rate Variability", value: hrv.map { "\(Int($0)) ms" } ?? "--", icon: "waveform.path.ecg")
            dataCard(title: "Steps Today", value: steps.map { "\(Int($0))" } ?? "--", icon: "figure.walk")
        }
    }

    private func dataCard(title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(.blue)
                .frame(width: 50)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    private var heartRatesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest 5 Heart Rates")
                .font(.headline)
                .padding(.horizontal)
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if heartRates.isEmpty {
                Text("Fetching heart rate data...")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(heartRates.prefix(5), id: \.self) { heartRate in
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                        Text("\(heartRate) BPM")
                            .font(.subheadline)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    private var anomalyView: some View {
        Group {
            if let details = anomalyDetails {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: details.isAnomaly ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(details.isAnomaly ? .red : .green)
                        Text(details.isAnomaly ? "Anomaly Detected" : "Heart Rate Pattern Normal")
                            .font(.headline)
                            .foregroundColor(details.isAnomaly ? .red : .green)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Anomaly Score: \(details.score, specifier: "%.2f")")
                            .font(.subheadline)
                        Text(details.isAnomaly ?
                             "Your current heart rate shows unusual pattern compared to your historical data." :
                             "Your heart rate is within normal patterns.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            }
        }
    }

    private var refreshButton: some View {
        Button(action: fetchAllHealthData) {
            HStack {
                Image(systemName: "arrow.clockwise")
                Text("Refresh Data")
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }

    private var demoButton: some View {
        EmptyView()
    }

    private var homeKitNavigationLink: some View {
        NavigationLink(destination: HomeKitDevicesView(homeKitManager: homeKitManager)) {
            HStack {
                Image(systemName: "house.fill")
                Text("HomeKit Devices")
            }
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }

    func requestHealthKitAuthorization() {
        healthKitManager.requestAuthorization { (success, error) in
            DispatchQueue.main.async {
                if success {
                    print("HealthKit authorization successful")
                    self.fetchAllHealthData()
                } else {
                    self.errorMessage = "HealthKit authorization failed: \(error?.localizedDescription ?? "Unknown error")"
                    print(self.errorMessage ?? "")
                }
            }
        }
    }

    func fetchHealthData() {
        healthKitManager.fetchBodyTemperature { (temperature, error) in
            if let error = error {
                self.errorMessage = "Failed to fetch temperature: \(error.localizedDescription)"
            } else {
                self.temperature = temperature
            }
        }

        healthKitManager.fetchHeartRate { (heartRate, error) in
            if let error = error {
                self.errorMessage = "Failed to fetch heart rate: \(error.localizedDescription)"
            } else {
                self.heartRate = heartRate
            }
        }
        
        healthKitManager.analyzeHeartRatePatterns { result in
            if let (isAnomaly, score) = result {
                self.anomalyDetails = (isAnomaly: isAnomaly, score: score)
            }
        }
    }
    func fetchHeartRates() {
        healthKitManager.fetchLatestHeartRates { (rates, error) in
            if let rates = rates {
                heartRates = rates
                errorMessage = nil
            } else if let error = error {
                errorMessage = "Failed to fetch heart rates: \(error.localizedDescription)"
                heartRates = []
            }
        }
    }


    func setupNotificationObserver() {
        NotificationCenter.default.addObserver(forName: Notification.Name("didReceiveMessage"), object: nil, queue: .main) { notification in
            if let message = notification.object as? [String: Any] {
                if let watchHeartRate = message["heartRate"] as? Double {
                    self.heartRate = watchHeartRate
                }
                else {
                    print("There is an error")
                }
                if message["temperature"] is Double {
                    self.temperature = 75
                }
            }
        }
    }
    
    func fetchAllHealthData() {
        fetchHealthData()
        fetchHeartRates()
        fetchHRV()
        fetchSteps()
        
        // Add heart rate pattern analysis with real data
        healthKitManager.analyzeHeartRatePatterns { result in
            if let (isAnomaly, score) = result {
                self.anomalyDetails = (isAnomaly: isAnomaly, score: score)
            }
        }
    }

    func fetchHRV() {
        healthKitManager.fetchHeartRateVariability { (hrv, error) in
            DispatchQueue.main.async {
                if let error = error {
                    if (error as NSError).code == 1 {
                        self.requestHealthKitAuthorization()
                    } else {
                        self.errorMessage = "Failed to fetch HRV: \(error.localizedDescription)"
                    }
                } else {
                    self.hrv = hrv
                    self.errorMessage = nil
                }
            }
        }
    }

    func fetchSteps() {
        healthKitManager.fetchSteps { (steps, error) in
            DispatchQueue.main.async {
                if let error = error {
                    if (error as NSError).code == 1 {
                        self.requestHealthKitAuthorization()
                    } else {
                        self.errorMessage = "Failed to fetch steps: \(error.localizedDescription)"
                    }
                } else {
                    self.steps = steps
                    self.errorMessage = nil
                }
            }
        }
    }
}
