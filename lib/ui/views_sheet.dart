import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/view_model.dart';
import '../state/app_state.dart';
import 'tv/tv_focusable.dart';
import 'tv/tv_text_field.dart';

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
                  child: Text(
                      'Sin vistas guardadas.\nUsa "Guardar vista" para crear una.',
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
              child: TvFocusable(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.of(context).pop();
                  _saveCurrentAsView(context, app);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bookmark_add_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Guardar vista actual'),
                    ],
                  ),
                ),
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
        content: SizedBox(
          width: 380,
          child: TvTextField(
            controller: controller,
            autofocus: true,
            labelText: 'Nombre',
            hintText: 'Casa, Oficina, Sucursal Norte…',
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
        ),
        actions: [
          TvFocusable(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(ctx).pop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 8),
          TvFocusable(
            borderRadius: BorderRadius.circular(8),
            backgroundColor: Theme.of(ctx).colorScheme.primary,
            onTap: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text('Guardar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: TvFocusable(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.of(context).pop();
          app.applyView(view);
        },
        child: ListTile(
          dense: true,
          leading: Icon(
            active ? Icons.radio_button_checked : Icons.dashboard_outlined,
            color: active ? const Color(0xFF00E5FF) : Colors.white54,
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
          trailing: TvFocusable(
            borderRadius: BorderRadius.circular(16),
            focusBorderColor: const Color(0xFFE5533D),
            onTap: () => app.deleteView(view.id),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.delete_outline,
                  size: 19, color: Color(0xFFE5533D)),
            ),
          ),
        ),
      ),
    );
  }
}