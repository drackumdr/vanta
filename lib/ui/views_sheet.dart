import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/view_model.dart';
import '../state/app_state.dart';

/// Panel de vistas personalizadas: aplicar, guardar, eliminar.
class ViewsSheet extends StatefulWidget {
  const ViewsSheet({super.key});

  @override
  State<ViewsSheet> createState() => _ViewsSheetState();
}

class _ViewsSheetState extends State<ViewsSheet> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('Vistas personalizadas',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            if (app.views.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text('Sin vistas guardadas.\nUsa "Guardar vista" para crear una.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: app.views.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) =>
                      _ViewRow(view: app.views[i]),
                ),
              ),
            const Divider(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _saveCurrentAsView(context, app);
                },
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Guardar vista actual'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCurrentAsView(BuildContext context, AppState app) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar vista'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Casa, Oficina, Sucursal Norte…',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await app.saveAsView(name);
  }
}

class _ViewRow extends StatelessWidget {
  const _ViewRow({required this.view});
  final SurveillanceView view;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final active = app.activeViewId == view.id;
    return ListTile(
      dense: true,
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.dashboard_outlined,
        color: active ? const Color(0xFF2F9BFF) : Colors.white54,
      ),
      title: Text(view.name,
          style: TextStyle(
            color: Colors.white,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          )),
      subtitle: Text(
        '${view.gridSize.count} cámaras · ${view.cells.whereType<String>().length} asignadas',
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      onTap: () {
        Navigator.of(context).pop();
        app.applyView(view);
      },
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 19),
        onPressed: () => app.deleteView(view.id),
      ),
    );
  }
}