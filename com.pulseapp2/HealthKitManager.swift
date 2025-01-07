import Foundation

import HealthKit

class HealthKitManager {
    let healthStore = HKHealthStore()
    private let isolationForest = IsolationForestAnalytics()
    @Published var anomalyDetected: Bool = false
    @Published var anomalyDetails: (isAnomaly: Bool, score: Double)?
    
    // Request authorization to access HealthKit data

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, nil)
            return
        }
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let bodyTemperatureType = HKObjectType.quantityType(forIdentifier: .bodyTemperature)!
        let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let stepsType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let healthDataToRead: Set = [heartRateType, bodyTemperatureType, hrvType, stepsType]

        healthStore.requestAuthorization(toShare: nil, read: healthDataToRead) { (success, error) in
            completion(success, error)
        }
    }

    // Fetch heart rate data
    func fetchHeartRate(completion: @escaping (Double?, Error?) -> Void) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: nil) { (_, results, error) in
            if let error = error {
                print("Error fetching heart rate: \(error.localizedDescription)")
                completion(nil, error)
                return
            }

            if let result = results?.last as? HKQuantitySample {
                let heartRate = result.quantity.doubleValue(for: HKUnit(from: "count/min"))
                print("Fetched heart rate: \(heartRate)")
                completion(heartRate, nil)
            } else {
                print("No heart rate data available")
                completion(nil, nil)
            }
        }
        healthStore.execute(query)
    }
    
    func fetchLatestHeartRates(completion: @escaping ([Double]?, Error?) -> Void) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false) // Sort by date, most recent first

        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 5, sortDescriptors: [sortDescriptor]) { (_, results, error) in
            if let error = error {
                completion(nil, error)
                return
            }

            if let samples = results as? [HKQuantitySample] {
                let heartRates = samples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }
                print("Latest 5 heart rates: \(heartRates)")
                completion(heartRates, nil)
            } else {
                completion(nil, nil)
            }
        }
        healthStore.execute(query)
    }


    // Fetch body temperature data
    func fetchBodyTemperature(completion: @escaping (Double?, Error?) -> Void) {
        let bodyTemperatureType = HKQuantityType.quantityType(forIdentifier: .bodyTemperature)!
        let query = HKSampleQuery(sampleType: bodyTemperatureType, predicate: nil, limit: 1, sortDescriptors: nil) { (_, results, error) in

            if let result = results?.first as? HKQuantitySample {
                let temperature = result.quantity.doubleValue(for: HKUnit.degreeCelsius())
                completion(temperature, nil)
            } else {

                completion(nil, error)

            }
        }
        healthStore.execute(query)
    }
    
    // Fetch heart rate variability data
    func fetchHeartRateVariability(completion: @escaping (Double?, Error?) -> Void) {
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: hrvType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { (_, results, error) in
            if let error = error {
                print("Error fetching HRV: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            
            if let result = results?.first as? HKQuantitySample {
                let hrv = result.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                print("Fetched HRV: \(hrv) ms")
                completion(hrv, nil)
            } else {
                print("No HRV data available")
                completion(nil, nil)
            }
        }
        healthStore.execute(query)
    }
    
    // Fetch steps data
    func fetchSteps(completion: @escaping (Double?, Error?) -> Void) {
        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { (_, result, error) in
            if let error = error {
                print("Error fetching steps: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            
            if let sum = result?.sumQuantity() {
                let steps = sum.doubleValue(for: HKUnit.count())
                print("Fetched steps: \(steps)")
                completion(steps, nil)
            } else {
                print("No steps data available")
                completion(nil, nil)
            }
        }
        healthStore.execute(query)
    }

    func analyzeHeartRateAnomalies(completion: @escaping (Bool) -> Void) {
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] (_, samples, error) in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample],
                  error == nil,
                  !samples.isEmpty else {
                completion(false)
                return
            }
            
            // Convert samples to heart rate values
            let heartRates = samples.map {
                $0.quantity.doubleValue(for: HKUnit(from: "count/min"))
            }
            
            // Get the most recent heart rate
            guard let currentHeartRate = heartRates.last else {
                completion(false)
                return
            }
            
            // Use Isolation Forest to detect anomalies
            let isAnomaly = self.isolationForest.detectAnomalies(
                historicalData: Array(heartRates.dropLast()),
                currentValue: currentHeartRate
            )
            
            DispatchQueue.main.async {
                self.anomalyDetected = isAnomaly
                completion(isAnomaly)
            }
        }
        
        healthStore.execute(query)
    }
    
    func analyzeHeartRatePatterns(completion: @escaping ((Bool, Double)?) -> Void) {
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { [weak self] (_, samples, error) in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample],
                  error == nil else {
                completion(nil)
                return
            }
            
            let heartRates = samples.map {
                $0.quantity.doubleValue(for: HKUnit(from: "count/min"))
            }
            
            guard let currentHeartRate = heartRates.last,
                  heartRates.count > 1 else {
                completion(nil)
                return
            }
            
            // Get historical data (excluding the current value)
            let historicalData = Array(heartRates.dropLast())
            
            // Calculate anomaly score
            let forest = self.isolationForest.buildForest(data: historicalData)
            let anomalyScore = self.isolationForest.calculateAnomalyScore(currentHeartRate, forest: forest)
            let isAnomaly = anomalyScore > 0.6 // threshold
            
            DispatchQueue.main.async {
                completion((isAnomaly, anomalyScore))
            }
        }
        
        healthStore.execute(query)
    }
    
}
