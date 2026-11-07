import '../lore/lore_repository.dart';
import '../lore/models/character_model.dart';
import '../lore/models/lore_item_model.dart';
import 'models/project_model.dart';
import 'models/story_node_model.dart';
import 'project_repository.dart';

/// A small finished project (one chapter, two characters tied to each other, one place) so a
/// new author can see the editor, the assistant context and the relationship map with
/// something in them. Everything is ordinary data: they can edit or delete it.
class SampleProject {
  static const chapterText =
      'La luz del faro llevaba nueve años apagada, y aun así Mara la vio girar desde la barca. '
      'Contó los intervalos mientras remaba. Doce segundos, los de siempre.\n\n'
      'En la mesa de la cocina había una taza de té. Tibia. Mara apoyó dos dedos en el borde y no dijo nada, '
      'porque no había nadie a quien decírselo.';

  /// Creates the project and returns it.
  static Future<ProjectModel> create(ProjectRepository projects, LoreRepository lore) async {
    final now = DateTime.now();
    final project = ProjectModel(
      id: ProjectRepository.generateId(),
      title: 'El faro (ejemplo)',
      synopsis: 'Mara vuelve a la isla donde su padre fue torrero y descubre que alguien mantiene encendido el faro.',
      createdAt: now,
      updatedAt: now,
    );
    await projects.saveProject(project);

    final chapter = ChapterModel(id: ProjectRepository.generateId(), projectId: project.id, title: 'Capítulo 1: La luz', order: 0);
    await projects.saveChapter(chapter);
    await projects.saveNode(StoryNodeModel(id: ProjectRepository.generateId(), chapterId: chapter.id, content: chapterText, timestamp: now));

    final mara = ProjectRepository.generateId();
    final padre = ProjectRepository.generateId();
    await lore.saveCharacter(CharacterModel(
      id: mara,
      name: 'Mara',
      appearance: 'Treinta y tantos años, manos agrietadas por la sal.',
      personalityTraits: const ['callada', 'obstinada'],
      motivation: 'Entender quién mantiene el faro y por qué.',
      relationships: [CharacterRelationship(characterId: padre, description: 'hija del torrero')],
      projectId: project.id,
    ));
    await lore.saveCharacter(CharacterModel(
      id: padre,
      name: 'Anselmo',
      appearance: 'Torrero durante treinta años; murió hace nueve.',
      motivation: 'Mantener la luz encendida.',
      secretsLimits: 'Nadie sabe qué guardaba en el cajón del faro.',
      relationships: [CharacterRelationship(characterId: mara, description: 'padre de Mara')],
      projectId: project.id,
    ));
    await lore.saveLoreItem(LoreItemModel(
      id: ProjectRepository.generateId(),
      name: 'El faro de Puerto Alba',
      category: LoreCategory.location,
      shortDescription: 'Torre blanca en un islote. La lámpara gira cada doce segundos.',
      projectId: project.id,
    ));
    return project;
  }
}
