//
//  ViewController.swift
//  PeertoPeer
//
//

import UIKit
import MultipeerConnectivity

class ViewController: UICollectionViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCBrowserViewControllerDelegate {
    
    var images = [UIImage]()
    var peerID = MCPeerID(displayName: UIDevice.current.name)
    var mcSession: MCSession?
    var mcNearbyServiceAdvertiser: MCNearbyServiceAdvertiser?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Selfie Share"
        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(showConnectionPrompt)),
            UIBarButtonItem(title: "Devices", style: .plain, target: self, action: #selector(showConnectedDevices))
        ]
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .camera, target: self, action: #selector(importPicture)),
            UIBarButtonItem(title: "Message", style: .plain, target: self, action: #selector(sendMessage))
        ]

        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession?.delegate = self
    }
    
    // MARK: - Image Picker
    @objc func importPicture() {
        let picker = UIImagePickerController()
        picker.allowsEditing = true
        picker.delegate = self
        present(picker, animated: true)
    }
    
    @objc func showConnectionPrompt() {
        let ac = UIAlertController(title: "Connect to others", message: nil, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "Host a session", style: .default, handler: startHosting))
        ac.addAction(UIAlertAction(title: "Join a session", style: .default, handler: joinSession))
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(ac, animated: true)
    }

    func startHosting(action: UIAlertAction) {
        guard let mcSession = mcSession else { return }
        mcNearbyServiceAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: "hws-project25")
        mcNearbyServiceAdvertiser?.delegate = self
        mcNearbyServiceAdvertiser?.startAdvertisingPeer()
        print("Started hosting a session.")
    }

    func joinSession(action: UIAlertAction) {
        guard let mcSession = mcSession else { return }
        let mcBrowser = MCBrowserViewController(serviceType: "hws-project25", session: mcSession)
        mcBrowser.delegate = self
        present(mcBrowser, animated: true)
    }
    
    @objc func sendMessage() {
        let ac = UIAlertController(title: "Send Message", message: nil, preferredStyle: .alert)
        ac.addTextField()

        ac.addAction(UIAlertAction(title: "Send", style: .default) { [weak self] _ in
            guard let text = ac.textFields?[0].text else { return }
            self?.send(text: text)
        })

        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(ac, animated: true)
    }
    
    func send(text: String) {
        guard let mcSession = mcSession else { return }
        guard mcSession.connectedPeers.count > 0 else { return }

        let messageData = Data(text.utf8)
        do {
            try mcSession.send(messageData, toPeers: mcSession.connectedPeers, with: .reliable)
        } catch {
            let ac = UIAlertController(title: "Send Error", message: error.localizedDescription, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        }
    }
    
    @objc func showConnectedDevices() {
        guard let mcSession = mcSession else { return }

        let peerNames = mcSession.connectedPeers.map { $0.displayName }
        let message = peerNames.isEmpty ? "No devices connected." : peerNames.joined(separator: "\n")

        let ac = UIAlertController(title: "Connected Devices", message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
    }



    
    // MARK: - MCNearbyServiceAdvertiserDelegate
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Show a custom alert for host to accept/reject the invitation
        let ac = UIAlertController(title: "\(peerID.displayName) wants to connect", message: nil, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
            invitationHandler(true, self.mcSession)
        })
        ac.addAction(UIAlertAction(title: "Decline", style: .cancel) { _ in
            invitationHandler(false, nil)
        })
        present(ac, animated: true)
    }

    // MARK: - Image Sharing
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = info[.editedImage] as? UIImage else { return }
        dismiss(animated: true)

        images.insert(image, at: 0)
        collectionView.reloadData()

        guard let mcSession = mcSession else { return }
        if mcSession.connectedPeers.count > 0 {
            if let imageData = image.pngData() {
                do {
                    try mcSession.send(imageData, toPeers: mcSession.connectedPeers, with: .reliable)
                } catch {
                    let ac = UIAlertController(title: "Send error", message: error.localizedDescription, preferredStyle: .alert)
                    ac.addAction(UIAlertAction(title: "OK", style: .default))
                    present(ac, animated: true)
                }
            }
        }
    }

    // MARK: - MCSessionDelegate
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("Connected to: \(peerID.displayName)")
        case .connecting:
            print("Connecting to: \(peerID.displayName)")
        case .notConnected:
            print("Disconnected from: \(peerID.displayName)")
            
            DispatchQueue.main.async { [weak self] in
                        let ac = UIAlertController(title: "Disconnected", message: "\(peerID.displayName) has left the session.", preferredStyle: .alert)
                        ac.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(ac, animated: true)
                    }
            
            
        @unknown default:
            print("Unknown state for: \(peerID.displayName)")
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            if let image = UIImage(data: data) {
                self?.images.insert(image, at: 0)
                self?.collectionView.reloadData()
            } else if let message = String(data: data, encoding: .utf8) {
                let ac = UIAlertController(title: "Message Received", message: "\(peerID.displayName): \(message)", preferredStyle: .alert)
                ac.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(ac, animated: true)
            }
        }
    }

    // Unused delegate methods (required but empty)
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // MARK: - MCBrowserViewControllerDelegate
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        dismiss(animated: true) {
            print("Successfully joined the session.")
        }
    }

    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        dismiss(animated: true) {
            print("User canceled the session.")
        }
    }

    // MARK: - Collection View Data Source
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return images.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageView", for: indexPath)
        if let imageView = cell.viewWithTag(1000) as? UIImageView {
            imageView.image = images[indexPath.item]
        }
        return cell
    }
}
