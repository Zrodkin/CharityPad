//
//  SquarePermissionService.swift
//  CharityPadWSquare
//
//  Created by Wilkes Shluchim on 5/18/25.
//
import Foundation
import CoreLocation
import CoreBluetooth
import SquareMobilePaymentsSDK

/// Service responsible for managing permissions required by Square SDK
class SquarePermissionService: NSObject, CLLocationManagerDelegate {
    // MARK: - Private Properties
    
    private weak var paymentService: SquarePaymentService?
    private lazy var locationManager = CLLocationManager()
    private var centralManager: CBCentralManager?
    
    // MARK: - Public Methods
    
    /// Configure the service with the payment service
    func configure(with paymentService: SquarePaymentService) {
        self.paymentService = paymentService
        locationManager.delegate = self
    }
    
    /// Request location permission required for Square SDK
    func requestLocationPermission() {
        let authorizationStatus = locationManager.authorizationStatus
        
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            updatePaymentError("Location permission is required for payments")
            print("Location permission denied - direct user to Settings app")
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location services already authorized")
        @unknown default:
            print("Unknown location authorization status")
        }
    }
    
    /// Request Bluetooth permissions required for Square readers
    func requestBluetoothPermissions() {
        if centralManager == nil {
            centralManager = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: true]
            )
        } else if centralManager?.state == .poweredOn {
            print("Bluetooth is already powered on")
        }
    }
    
    /// Check if location permission is granted
    func isLocationPermissionGranted() -> Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
    
    /// Check if Bluetooth is available and powered on
    func isBluetoothAvailable() -> Bool {
        guard let centralManager = centralManager else {
            // Initialize Bluetooth manager if needed
            requestBluetoothPermissions()
            return false
        }
        
        return centralManager.state == .poweredOn
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location permission granted")
            // Notify the payment service that location permission is now available
            paymentService?.connectToReader()
            
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.updatePaymentError("Location permission is required for Square payments")
                self?.updateConnectionStatus("Location access denied")
            }
            
        case .notDetermined:
            print("Location permission not determined yet")
            
        @unknown default:
            print("Unknown location authorization status")
        }
    }
    
    // MARK: - Private Methods
    
    /// Update the connection status in the payment service
    private func updateConnectionStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.connectionStatus = status
        }
    }
    
    /// Update payment error in the payment service
    private func updatePaymentError(_ error: String) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.paymentError = error
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension SquarePermissionService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on and ready for use")
            // Notify payment service that Bluetooth is now available
            paymentService?.connectToReader()
            
        case .poweredOff:
            DispatchQueue.main.async { [weak self] in
                self?.updatePaymentError("Bluetooth is powered off. Please turn it on to use card readers.")
                self?.updateConnectionStatus("Bluetooth turned off")
                
                // Update reader connected state
                if let paymentService = self?.paymentService {
                    paymentService.isReaderConnected = false
                }
            }
            
        case .resetting:
            print("Bluetooth is resetting")
            
        case .unauthorized:
            DispatchQueue.main.async { [weak self] in
                self?.updatePaymentError("Bluetooth permission is required for card readers")
                self?.updateConnectionStatus("Bluetooth permission denied")
                
                // Update reader connected state
                if let paymentService = self?.paymentService {
                    paymentService.isReaderConnected = false
                }
            }
            
        case .unsupported:
            DispatchQueue.main.async { [weak self] in
                self?.updatePaymentError("This device does not support Bluetooth")
                self?.updateConnectionStatus("Bluetooth not supported")
                
                // Update reader connected state
                if let paymentService = self?.paymentService {
                    paymentService.isReaderConnected = false
                }
            }
            
        case .unknown:
            print("Bluetooth state is unknown")
            
        @unknown default:
            print("Unknown Bluetooth state")
        }
    }
}
