//
//  FirebaseService.swift
//  Developer Suite
//
//  Created by RAGHAVAN RENGANATHAN on 12/4/18.
//  Copyright © 2018 RAGHAVAN RENGANATHAN. All rights reserved.
//

import Foundation
import FirebaseFirestore
import CoreData
import MessageKit

final class FirebaseService {
    // MARK: Properties
    // Making the class singleton
    public class var shared: FirebaseService {
        struct FirebaseServiceInstance {
            static let instance: FirebaseService = FirebaseService()
        }
        return FirebaseServiceInstance.instance
    }
    
    private let db: Firestore
    
    private init() {
        db = Firestore.firestore()
        let settings: FirestoreSettings = db.settings
        settings.areTimestampsInSnapshotsEnabled = true
        db.settings = settings
    }
}

// MARK: Firebase fetch service
extension FirebaseService {
    
    // MARK: Private methods
    /**
     Constructs the ChatMO collection from the QueryDocumentSnapshots
     - Parameter chatDocuments: The array of all the chat document snapshots
     - Parameter user: User for whom the chat is being created
     - Parameter completion: The completion closure that has to be called with the fetched chats
     */
    private func constructChatMO(fromDocumentSnapshot chatDocuments: [QueryDocumentSnapshot], forUser user: UserMO, completion: @escaping () -> ()) {
        var chats: [ChatMO] = []
        let context: NSManagedObjectContext = DataManager.shared.context
        let group: DispatchGroup = DispatchGroup()
        
        for document: QueryDocumentSnapshot in chatDocuments {
            // Make async call
            group.enter()

            let data: [String: Any] = document.data()
            guard
            let participants: [String] = data["participants"] as? [String],
                participants.count == 2 else {
                    continue
            }
            let messages: [String] = data["messages"] as? [String] ?? []
            var chat: ChatMO
            
            do {
                if let _chat: ChatMO = try ChatsFetchRequest.fetchChat(withID: document.documentID) {
                    chat = _chat
                    group.leave()
                } else {
                    guard let _chat: ChatMO = ChatMO.getInstance(context: context) else {
                        group.leave()
                        Utils.log("CoreDataError: Unable to create an instance for Chats")
                        return
                    }
                    chat = _chat
                    chat.id = document.documentID
                    // Fetch the receipients from the participants array
                    if (participants[0] == user.uid) {
                        // If current user is in the 0th index, then the receipient is in the 1st index
                        chat.recipientId = participants[1]
                    } else {
                        // Vice versa
                        chat.recipientId = participants[0]
                    }
                    
                    // Fetching receipients data and messages asynchronously
                    let innerGroup: DispatchGroup = DispatchGroup()
                    
                    for messageID: String in messages {
                        innerGroup.enter()
                        
                        fetchMessage(withId: messageID) { messageMO in
                            if let message: MessageMO = messageMO {
                                chat.addToMessages(message)
                            }
                            innerGroup.leave()
                        }
                    }
                    
                    innerGroup.enter()
                    let userDocumentReference: DocumentReference = db.collection("users").document(chat.recipientId!)
                    userDocumentReference.getDocument { (document, error) in
                        if let _ = error {
                            Utils.log("FirebaseError: Unable to fetch user data")
                        } else {
                            chat.recipientName = document?.data()?["displayName"] as? String
                            chats.append(chat)
                        }
                        innerGroup.leave()
                    }
                    
                    innerGroup.notify(queue: .main) {
                        group.leave()
                    }
                }
            } catch {
                group.leave()
                Utils.log("CoreDataError: Unable to fetch an instance for Chats")
                return
            }
        }
        
        group.notify(queue: .main) {
            user.addToChats(NSOrderedSet(array: chats))
            // Once all the data are loaded, call the comnpletion with loaded chats
            completion()
        }
    }
    
    // MARK: Fetching reference to documents
    /**
     Fetches the chats for the user specified
     - Parameter user: The user model object
     - Parameter completion: The completion closure that has to be called with the fetched chats
     */
    func fetchChats(forUser user: UserMO, completion: @escaping () -> ()) {
        let chatQuery: Query = db.collection("chats").whereField("participants", arrayContains: user.uid!)
        let chatMOConstructor = constructChatMO(fromDocumentSnapshot:forUser:completion:)
        
        chatQuery.getDocuments { (querySnapshot, error) in
            if let _ = error {
                Utils.log("FirebaseError: Unable to fetch chats")
                completion()
            } else {
                chatMOConstructor(querySnapshot!.documents, user) {
                    // Fetch all the messages
                    
                    completion()
                }
            }
        }
    }
    
    /**
     Fetches the message given a message id
     - Parameter id: The id of the message that has to be fetched
     - Parameter completion: The completion closure that has to be called with the fetched chats
     */
    func fetchMessage(withId id: String, completion: @escaping (MessageMO?) -> ()) {
        let messageDocumentReference: DocumentReference = db.collection("messages").document(id)
        
        messageDocumentReference.getDocument { (document, error) in
            if let _ = error {
                Utils.log("FirebaseError: Unable to fetch message data")
            } else {
                let message: [String: Any] = document!.data()!
                guard let messageMO: MessageMO = MessageMO.getInstance(context: DataManager.shared.context) else {
                    Utils.log("CoreDataError: Unable to create an instance for Message")
                    completion(nil)
                    return
                }
                messageMO.id = document?.documentID
                messageMO.senderId = message["sender_uid"] as? String
                messageMO.message = message["message"] as? String
                messageMO.timestamp = (message["timestamp"] as? Timestamp)?.dateValue() as NSDate?
                
                completion(messageMO)
            }
        }
    }
    
    /**
     Fetch an avatar for the given sender
     - Parameter sender: The sender object with uid and display name
     - Returns: The Avatar instance for the sender
     */
    func getAvatarFor(sender: Sender) -> Avatar {
        let firstName: String? = sender.displayName.components(separatedBy: " ").first
        let lastName: String? = sender.displayName.components(separatedBy: " ").first
        let initials: String = "\(firstName?.first ?? "A")\(lastName?.first ?? "A")"
        return Avatar(image: nil, initials: initials)
    }
}

// MARK: Firebase add service
extension FirebaseService {
    /**
     Adds a message to a chat for a sender
     - Parameter message: The message to be saved
     - Parameter chat: The  chat to which this message has to be added
     - Parameter sender: The user who is sending this message
     - Parameter completion: The code block that has to be executed once this operation is done
     */
    func addMessage(_ message: String, forChat chat: ChatMO, andSender sender: Sender, completion: @escaping (String) -> ()) {
        var messageRef: DocumentReference? = nil
        messageRef = db.collection("messages").addDocument(data: [
            "message": message,
            "sender_uid": sender.id,
            "timestamp": FieldValue.serverTimestamp()
        ]) { error in
            if error == nil {
                // Add this message Id to the chat model
                let chatRef: DocumentReference = self.db.collection("chats").document(chat.id!)
                chatRef.setData([
                    "messages": FieldValue.arrayUnion([messageRef!.documentID])
                ], merge: true) { error in
                    if error == nil {
                        completion(messageRef!.documentID)
                    }
                }
            }
        }
    }
}
