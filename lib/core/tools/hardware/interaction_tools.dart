/// Interaction tools: ask the user a question mid-turn.
library;

import '../tool.dart';

/// Blocks on a user prompt in the chat UI. When no interactive UI is attached
/// (ctx.askUser is null) it tells the model to proceed with a safe default
/// instead of hanging.
class AskUserTool extends Tool {
  @override
  String get name => 'ask_user';

  @override
  String get category => 'Core';

  @override
  bool get isCoreTool => true;

  @override
  String get description =>
      'Ask the user a question when you need confirmation, a decision, or '
      'free-form input before proceeding. Blocks until the user responds. On '
      'cancel, returns a cancellation message - stop and await instructions. '
      'If interaction is unavailable, returns a fallback message; proceed with '
      'a safe default.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'question': {
        'type': 'string',
        'description': 'The question or prompt to show the user.',
      },
      'choices': {
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
        'description':
            'Predefined options the user can pick from. Omit for free-text.',
      },
      'allowFreeText': {
        'type': 'boolean',
        'description':
            'Also show a free-text input alongside the choices. Default false.',
      },
      'defaultChoice': {
        'type': 'string',
        'description': 'Optional default selection or input placeholder.',
      },
    },
    'required': <String>['question'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final question = requireString(args, 'question');
    final askUser = ctx.askUser;
    if (askUser == null) {
      return 'User interaction is not available right now. Proceed with a safe '
          'default and note the assumption in your answer.';
    }

    final choices = args['choices'];
    final request = AskUserRequest(
      question: question,
      choices: choices is List
          ? choices.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const <String>[],
      allowFreeText: optionalBool(args, 'allowFreeText', false),
      defaultChoice: optionalString(args, 'defaultChoice'),
    );

    final response = await askUser(request);
    if (response.cancelled) {
      return 'The user cancelled the prompt. Stop the current task and await '
          'further instructions.';
    }
    return response.answer;
  }
}

final List<Tool> interactionTools = <Tool>[
  AskUserTool(),
];
