class Workspace {
  const Workspace({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  Map<String, String> toMap() => {'id': id, 'name': name};

  factory Workspace.fromMap(Map<String, String> map) {
    return Workspace(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
    );
  }

  Workspace copyWith({String? id, String? name}) {
    return Workspace(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Workspace &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Workspace(id: $id, name: $name)';
}
