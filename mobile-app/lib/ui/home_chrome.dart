import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/wsf.dart';
import 'guardian_orb.dart';
import 'kit.dart';
import 'motion.dart';

/// What kind of ground the user is standing on. The whole home sheet takes
/// its colour, copy and the guardian's mood from this.
enum ZoneState { calm, caution, danger }

extension ZoneLook on ZoneState {
  OrbMood get mood => switch (this) {
        ZoneState.calm => OrbMood.calm,
        ZoneState.caution => OrbMood.caution,
        ZoneState.danger => OrbMood.alert,
      };

  Color get bg => switch (this) {
        ZoneState.calm => Wsf.ink3,
        ZoneState.caution => Wsf.amber,
        ZoneState.danger => Wsf.coral,
      };

  Color get fg => this == ZoneState.calm ? Wsf.bone : Wsf.ink;

  Color get dim => switch (this) {
        ZoneState.calm => Wsf.boneDim,
        ZoneState.caution => const Color(0xFF5C4300),
        ZoneState.danger => const Color(0xFF5E1405),
      };

  Color get accent => this == ZoneState.calm ? Wsf.volt : Wsf.ink;

  String get eyebrow => switch (this) {
        ZoneState.calm => 'guardian on',
        ZoneState.caution => 'heads up',
        ZoneState.danger => 'danger',
      };

  // Calm is conversational. The other two say exactly what is happening.
  (String, String) get headline => switch (this) {
        ZoneState.calm => ("you're in a", 'calm zone.'),
        ZoneState.caution => ('Moderate-risk zone.', 'stay aware.'),
        ZoneState.danger => ('High-risk zone.', 'stay alert.'),
      };
}

/// Top of the home sheet: the guardian and a two-line read on where you are.
class StatusHeader extends StatelessWidget {
  const StatusHeader({super.key, required this.zone, required this.listening, this.onOrbTap});
  final ZoneState zone;

  /// Whether the audio sentinel is running.
  final bool listening;
  final VoidCallback? onOrbTap;

  @override
  Widget build(BuildContext context) {
    final (lead, accent) = zone.headline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 20, 18),
      child: Row(
        children: [
          GuardianOrb(
            size: 86,
            mood: zone == ZoneState.calm && listening ? OrbMood.listening : zone.mood,
            glow: zone == ZoneState.calm,
            onTap: onOrbTap,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: Wsf.base,
              switchInCurve: Wsf.expoOut,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              child: Column(
                key: ValueKey(zone),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Eyebrow(zone.eyebrow, color: zone.dim),
                      if (listening) ...[
                        const SizedBox(width: 8),
                        Tag(
                          'listening',
                          bg: zone.accent,
                          fg: zone == ZoneState.calm ? Wsf.voltDeep : zone.bg,
                          icon: Icons.graphic_eq_rounded,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(lead, style: Wsf.display(27, color: zone.fg, height: 1)),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(accent, style: Wsf.serif(30, color: zone.accent, height: 1.05)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The grab bar at the top of a sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key, this.color = Wsf.boneFaint});
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 44,
          height: 5,
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
      );
}

/// Bottom dock: home, a raised SOS button with a heartbeat ring, profile.
class NavDock extends StatefulWidget {
  const NavDock({
    super.key,
    required this.index,
    required this.onHome,
    required this.onSos,
    required this.onProfile,
  });

  final int index;
  final VoidCallback onHome;
  final VoidCallback onSos;
  final VoidCallback onProfile;

  @override
  State<NavDock> createState() => _NavDockState();
}

class _NavDockState extends State<NavDock> with SingleTickerProviderStateMixin {
  late final AnimationController _beat =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Wsf.ink,
          border: Border(top: BorderSide(color: Wsf.line, width: 1.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 70,
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    icon: Icons.near_me_rounded,
                    label: 'map',
                    selected: widget.index == 0,
                    onTap: widget.onHome,
                  ),
                ),
                // The SOS button stands proud of the dock.
                Transform.translate(
                  offset: const Offset(0, -16),
                  child: Pressable(
                    scale: 0.9,
                    haptic: false,
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      widget.onSos();
                    },
                    child: SizedBox.square(
                      dimension: 96,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _beat,
                            builder: (_, __) {
                              final v = Curves.easeOut.transform(_beat.value);
                              return Container(
                                width: 72 + 24 * v,
                                height: 72 + 24 * v,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Wsf.coral.withValues(alpha: 0.7 * (1 - v)), width: 2.5),
                                ),
                              );
                            },
                          ),
                          Container(
                            width: 74,
                            height: 74,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Wsf.coral,
                              shape: BoxShape.circle,
                              border: Border.all(color: Wsf.ink, width: 5),
                            ),
                            child: Text('SOS', style: Wsf.display(21, color: Wsf.ink, height: 1)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.person_rounded,
                    label: 'you',
                    selected: widget.index == 2,
                    onTap: widget.onProfile,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Wsf.volt : Wsf.boneFaint;
    return Pressable(
      scale: 0.9,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 5),
          Eyebrow(label, color: color, size: 10.5),
        ],
      ),
    );
  }
}

/// One entry of the map's side dock.
class DockAction {
  const DockAction({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.loading = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final bool loading;
  final String? tooltip;
}

/// Vertical capsule of map tools.
class MapDock extends StatelessWidget {
  const MapDock({super.key, required this.actions});
  final List<DockAction> actions;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Wsf.ink,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Wsf.line, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, a) in actions.indexed) ...[
              if (i > 0) const SizedBox(height: 5),
              Tooltip(
                message: a.tooltip ?? '',
                child: DiscButton(
                  icon: a.icon,
                  size: 46,
                  bg: a.active ? Wsf.volt : Wsf.ink3,
                  fg: a.active ? Wsf.voltDeep : Wsf.bone,
                  border: null,
                  loading: a.loading,
                  onTap: a.onTap,
                ),
              ),
            ],
          ],
        ),
      );
}

/// A nearby safe place, as a receipt row.
class SafeSpotTile extends StatelessWidget {
  const SafeSpotTile({
    super.key,
    required this.icon,
    required this.title,
    required this.distanceKm,
    required this.address,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final double distanceKm;
  final String address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        scale: 0.98,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
          decoration: BoxDecoration(
            color: Wsf.ink2,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Wsf.line, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: Wsf.ink4, shape: BoxShape.circle),
                child: Icon(icon, color: Wsf.volt, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Wsf.body(size: 15.5, color: Wsf.bone, weight: FontWeight.w600),
                    ),
                    if (address.isNotEmpty)
                      Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Wsf.body(size: 13, color: Wsf.boneFaint),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Eyebrow('${distanceKm.toStringAsFixed(1)} km', color: Wsf.volt),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_outward_rounded, color: Wsf.boneFaint, size: 18),
            ],
          ),
        ),
      );
}

/// Colours for a route's risk level, shared by the preview card, the trip
/// sheet and the line drawn on the map.
({Color bg, Color fg, Color dim, String label}) riskLook(String level) => switch (level) {
      'high' => (bg: Wsf.coral, fg: Wsf.ink, dim: const Color(0xFF5E1405), label: 'high risk'),
      'medium' => (bg: Wsf.amber, fg: Wsf.ink, dim: const Color(0xFF5C4300), label: 'caution'),
      _ => (bg: Wsf.volt, fg: Wsf.ink, dim: const Color(0xFF465212), label: 'safe route'),
    };
