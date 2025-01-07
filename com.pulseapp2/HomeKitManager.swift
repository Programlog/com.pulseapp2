import HomeKit

class HomeKitManager: NSObject, ObservableObject, HMHomeManagerDelegate {
    @Published var devices: [HMAccessory] = []
    private var homeManager = HMHomeManager()

    override init() {
        super.init()
        homeManager.delegate = self
    }
    
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        fetchDevices()
    }
    
    func fetchDevices() {
        devices = homeManager.homes.flatMap { $0.accessories }
    }
    
    func addAndSetupAccessories() {
        guard let home = homeManager.homes.first else {
            print("No homes are available")
            return
        }
        
        home.addAndSetupAccessories { error in
            if let error = error {
                print("Error setting up accessories: \(error.localizedDescription)")
            } else {
                // Reload devices list after adding
                self.fetchDevices()
            }
        }
    }
    
    // Updated function to toggle device state
    func toggleDevice(_ device: HMAccessory) {
        // Iterate through all services to find the Power State characteristic
        for service in device.services {
            if let powerCharacteristic = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypePowerState }) {
                let currentValue = powerCharacteristic.value as? Bool ?? false
                powerCharacteristic.writeValue(!currentValue) { error in
                    if let error = error {
                        print("Error toggling device: \(error.localizedDescription)")
                    } else {
                        print("Device toggled successfully")
                        DispatchQueue.main.async {
                            self.fetchDevices()
                        }
                    }
                }
                return
            }
        }
        print("Device does not support power state characteristic")
    }
}
