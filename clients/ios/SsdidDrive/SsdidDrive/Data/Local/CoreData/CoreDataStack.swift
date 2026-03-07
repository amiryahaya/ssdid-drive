import Foundation
import CoreData

/// Core Data stack manager for local notification storage.
///
/// Uses a programmatically defined model to avoid Xcode model editor dependencies.
/// This approach is cleaner for CI/CD and allows model definition in code.
///
/// Thread Safety:
/// - `viewContext`: Use only on main thread for reading
/// - `writeContext`: Single dedicated context for all write operations (serialized)
final class CoreDataStack {

    // MARK: - Singleton

    static let shared = CoreDataStack()

    // MARK: - Constants

    private static let modelName = "SsdidDriveNotifications"
    private static let notificationEntityName = "NotificationEntity"

    // MARK: - State

    /// Tracks whether persistent stores loaded successfully
    private(set) var isStoreLoaded = false
    private var storeLoadError: Error?

    // MARK: - Core Data Stack

    /// The managed object model defining our entities
    private lazy var managedObjectModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()
        model.entities = [createNotificationEntity()]
        return model
    }()

    /// The persistent container
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(
            name: Self.modelName,
            managedObjectModel: managedObjectModel
        )

        // Configure for lightweight migration
        let description = NSPersistentStoreDescription()
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error as NSError? {
                self?.storeLoadError = error
                self?.isStoreLoaded = false

                #if DEBUG
                print("CoreDataStack: Failed to load persistent stores: \(error), \(error.userInfo)")
                #endif

                // Log to crash reporting in production
                #if !DEBUG
                SentryConfig.shared.captureError(error)
                #endif

                // Attempt recovery: delete corrupted store and retry
                if let storeURL = storeDescription.url {
                    self?.attemptStoreRecovery(container: container, storeURL: storeURL, description: storeDescription)
                }
            } else {
                self?.isStoreLoaded = true
                self?.storeLoadError = nil
            }
        }

        // Configure for concurrency
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }()

    /// Single dedicated background context for all write operations.
    /// Using a single context prevents race conditions between concurrent writes.
    private lazy var _writeContext: NSManagedObjectContext = {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }()

    /// Main thread context for reading
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    /// Dedicated background context for writing.
    /// All write operations should use this single context to prevent race conditions.
    var writeContext: NSManagedObjectContext {
        _writeContext
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Store Recovery

    /// Attempts to recover from a corrupted store by deleting and recreating it
    private func attemptStoreRecovery(
        container: NSPersistentContainer,
        storeURL: URL,
        description: NSPersistentStoreDescription
    ) {
        #if DEBUG
        print("CoreDataStack: Attempting store recovery...")
        #endif

        do {
            // Remove corrupted store files
            let fileManager = FileManager.default
            let storePath = storeURL.path

            // Remove main store file and associated files (-shm, -wal)
            for suffix in ["", "-shm", "-wal"] {
                let filePath = storePath + suffix
                if fileManager.fileExists(atPath: filePath) {
                    try fileManager.removeItem(atPath: filePath)
                }
            }

            // Retry loading
            container.loadPersistentStores { [weak self] _, retryError in
                if let retryError = retryError {
                    self?.isStoreLoaded = false
                    self?.storeLoadError = retryError
                    #if DEBUG
                    print("CoreDataStack: Recovery failed: \(retryError)")
                    #endif
                } else {
                    self?.isStoreLoaded = true
                    self?.storeLoadError = nil
                    #if DEBUG
                    print("CoreDataStack: Recovery successful - store recreated")
                    #endif
                }
            }
        } catch {
            #if DEBUG
            print("CoreDataStack: Failed to delete corrupted store: \(error)")
            #endif
        }
    }

    // MARK: - Entity Definitions

    /// Creates the NotificationEntity description programmatically
    private func createNotificationEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = Self.notificationEntityName
        entity.managedObjectClassName = NSStringFromClass(NotificationEntity.self)

        // Attributes
        var attributes: [NSAttributeDescription] = []

        // id - String, required, indexed
        let idAttribute = NSAttributeDescription()
        idAttribute.name = "id"
        idAttribute.attributeType = .stringAttributeType
        idAttribute.isOptional = false
        attributes.append(idAttribute)

        // userId - String, required, indexed
        let userIdAttribute = NSAttributeDescription()
        userIdAttribute.name = "userId"
        userIdAttribute.attributeType = .stringAttributeType
        userIdAttribute.isOptional = false
        attributes.append(userIdAttribute)

        // type - String, required
        let typeAttribute = NSAttributeDescription()
        typeAttribute.name = "type"
        typeAttribute.attributeType = .stringAttributeType
        typeAttribute.isOptional = false
        attributes.append(typeAttribute)

        // title - String, required
        let titleAttribute = NSAttributeDescription()
        titleAttribute.name = "title"
        titleAttribute.attributeType = .stringAttributeType
        titleAttribute.isOptional = false
        attributes.append(titleAttribute)

        // message - String, required
        let messageAttribute = NSAttributeDescription()
        messageAttribute.name = "message"
        messageAttribute.attributeType = .stringAttributeType
        messageAttribute.isOptional = false
        attributes.append(messageAttribute)

        // isRead - Boolean, required, indexed, default false
        let isReadAttribute = NSAttributeDescription()
        isReadAttribute.name = "isRead"
        isReadAttribute.attributeType = .booleanAttributeType
        isReadAttribute.isOptional = false
        isReadAttribute.defaultValue = false
        attributes.append(isReadAttribute)

        // actionType - String, optional
        let actionTypeAttribute = NSAttributeDescription()
        actionTypeAttribute.name = "actionType"
        actionTypeAttribute.attributeType = .stringAttributeType
        actionTypeAttribute.isOptional = true
        attributes.append(actionTypeAttribute)

        // actionResourceId - String, optional
        let actionResourceIdAttribute = NSAttributeDescription()
        actionResourceIdAttribute.name = "actionResourceId"
        actionResourceIdAttribute.attributeType = .stringAttributeType
        actionResourceIdAttribute.isOptional = true
        attributes.append(actionResourceIdAttribute)

        // createdAt - Date, required, indexed
        let createdAtAttribute = NSAttributeDescription()
        createdAtAttribute.name = "createdAt"
        createdAtAttribute.attributeType = .dateAttributeType
        createdAtAttribute.isOptional = false
        attributes.append(createdAtAttribute)

        // readAt - Date, optional
        let readAtAttribute = NSAttributeDescription()
        readAtAttribute.name = "readAt"
        readAtAttribute.attributeType = .dateAttributeType
        readAtAttribute.isOptional = true
        attributes.append(readAtAttribute)

        entity.properties = attributes

        // Indexes for efficient queries
        let idIndex = NSFetchIndexDescription(
            name: "byId",
            elements: [NSFetchIndexElementDescription(property: idAttribute, collationType: .binary)]
        )
        let userIdIndex = NSFetchIndexDescription(
            name: "byUserId",
            elements: [NSFetchIndexElementDescription(property: userIdAttribute, collationType: .binary)]
        )
        let isReadIndex = NSFetchIndexDescription(
            name: "byIsRead",
            elements: [NSFetchIndexElementDescription(property: isReadAttribute, collationType: .binary)]
        )
        let createdAtIndex = NSFetchIndexDescription(
            name: "byCreatedAt",
            elements: [NSFetchIndexElementDescription(property: createdAtAttribute, collationType: .binary)]
        )

        entity.indexes = [idIndex, userIdIndex, isReadIndex, createdAtIndex]

        // Uniqueness constraint on id
        entity.uniquenessConstraints = [[idAttribute]]

        return entity
    }

    // MARK: - Save

    /// Saves changes in the view context
    func saveViewContext() {
        let context = viewContext
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            #if DEBUG
            print("CoreDataStack: Failed to save view context: \(error)")
            #endif
        }
    }
}
