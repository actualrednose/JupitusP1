# cutscene_action_move.gd
# -----------------------------------------------------------------------------
# Moves a character (or any Node3D) to a destination over a duration.
#
# Uses a Tween for smooth movement with easing.
#
# Usage:
#   - Set `actor` to the NodePath of the character to move
#     (e.g., the player, an NPC, a robber)
#   - Set `destination` to the NodePath of a Marker3D (the destination)
#   - Set `duration` (seconds) and easing
#
# The cutscene waits for the movement to complete before moving on.
#
# Note: This moves the actor instantly via Tween — it doesn't use the
# CharacterBody3D's velocity system. This means no collision detection
# during the move. If you need collision-aware movement, you'd need to
# set the velocity and call move_and_slide() in _physics_process instead.
# For cutscenes, tween-based movement is usually what you want (more
# controlled, no physics surprises).
# -----------------------------------------------------------------------------

extends CutsceneAction
class_name CutsceneActionMove

## Path to the node to move. Can be relative to the scene root or absolute.
## Examples: "Player", "Robber", "NPCs/Shopkeeper"
@export var actor: NodePath = ""

## Path to a Marker3D (or any Node3D) marking the destination.
## The actor will be tweened to this node's global_position.
@export var destination: NodePath = ""

## How long the move takes, in seconds.
@export var duration: float = 1.0

## Easing function for the move.
## LINEAR = constant speed, SINE = smooth start/end, QUAD = sharper ease
@export_enum("Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Expo") var ease_type: int = 1  # Sine

## Whether the actor should face the direction of movement.
## If true, and the actor has a `face_direction` method, the actor will
## face the destination at the start of the move.
@export var face_destination: bool = true


func execute(cutscene_player: Node) -> void:
        if actor.is_empty() or destination.is_empty():
                push_warning("CutsceneActionMove: actor or destination path is empty")
                return

        # NOTE: get_node_or_null is a Node method, not a SceneTree method.
        # We call it on cutscene_player (which is a Node).
        #
        # When you assign a NodePath in the Inspector by clicking a node, Godot
        # stores the path relative to the node that owns the property (or to the
        # scene root, depending on context). Both relative and absolute paths
        # work with get_node_or_null — Godot evaluates relative paths relative
        # to the node the method is called on, and absolute paths (starting with /)
        # from the scene root.
        #
        # So we just pass the NodePath as-is — no conversion needed.
        var actor_node: Node3D = cutscene_player.get_node_or_null(actor) as Node3D
        var dest_node: Node3D = cutscene_player.get_node_or_null(destination) as Node3D

        if actor_node == null:
                push_warning("CutsceneActionMove: actor node not found at path '%s'" % actor)
                return

        if dest_node == null:
                push_warning("CutsceneActionMove: destination node not found at path '%s'" % destination)
                return

        # Optionally face the destination before moving
        if face_destination and actor_node.has_method("face_direction"):
                var direction_to_dest: Vector3 = dest_node.global_position - actor_node.global_position
                actor_node.face_direction(direction_to_dest)

        # Create a tween to move the actor.
        # We tween global_position so it works regardless of the actor's parent.
        var tween: Tween = cutscene_player.create_tween()
        tween.tween_property(actor_node, "global_position", dest_node.global_position, duration)
        tween.set_trans(_get_tween_trans())
        tween.set_ease(Tween.EASE_IN_OUT)

        # Wait for the tween to finish
        await tween.finished


func _get_tween_trans() -> int:
        # Map the string enum to Tween transition types
        match ease_type:
                0: return Tween.TRANS_LINEAR
                1: return Tween.TRANS_SINE
                2: return Tween.TRANS_QUAD
                3: return Tween.TRANS_CUBIC
                4: return Tween.TRANS_QUART
                5: return Tween.TRANS_QUINT
                6: return Tween.TRANS_EXPO
                _: return Tween.TRANS_SINE


func skip(_cutscene_player: Node) -> void:
        # When skipping, we leave the tween running — the cutscene player will
        # stop awaiting execute() and move on. The tween continues in the
        # background but doesn't block anything.
        #
        # An alternative would be to track the tween and kill it here, then
        # snap the actor to the destination. For now, leave it running.
        pass
