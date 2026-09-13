/// Base class for Firestore read/write failures raised by the data services.
class FirestoreException implements Exception {
  final String message;

  const FirestoreException(this.message);

  @override
  String toString() => message;
}

/// Raised when a requested document does not exist.
class DocumentNotFoundException extends FirestoreException {
  const DocumentNotFoundException(String document)
      : super('$document does not exist.');
}