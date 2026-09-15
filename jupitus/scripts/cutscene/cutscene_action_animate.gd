# cutscene_action_animate.gd
# -----------------------------------------------------------------------------
# Plays an animation on an AnimatedSprite3D (or a node containing one).
#
# Use for character reactions during cutscenes: a "surprised" pose, a
# "wave" animation, etc.
#
# Usage:
#   - Set `actor` to the NodePath of the character (or the AnimatedSprite3D itself)
#   - Set `animation` to the animation name (e.g., "idle", "walk", "surprised")
#   - Set `wait_for_completion` based on whether the cutscene should pause
#     until the animation finishes
#
# Note: For one-shot animations (e.g., "wave"), set wait_for_completion = true
# so the cutscene doesn't move on before the animation is done.
# For looping animations (e.g., switching to "idle" pose), set
# wait_for_completion = false, since looping animations never finish.
# -----------------------------------------------------------------------------

extends CutsceneAction
class_name CutsceneActionAnimate

## Path to the character node. Can be the AnimatedSprite3D itself, or a
## parent node (e.g., the CharacterBody3D). If a parent is specified, the
## action searches for a child named "Sprite" or the first AnimatedSprite3D.
@export var actor: NodePath = ""

## The animation name to play. Must exist in the SpriteFrames resource.
## Use StringName (&"...") for slight perf optimization.
@export var animation: StringName = &"idle"

## If true, the cutscene waits for the animation to finish before moving on.
## If false, the cutscene continues immediately after starting the animation.
##
## Set to TRUE for one-shot animations (wave, surprised, attack).
## Set to FALSE for looping animations (idle, walk) that should persist.
@export var wait_for_completion: bool = false


func execute(cutscene_player: Node) -> void:
        if actor.is_empty():
                push_warning("CutsceneActionAnimate: actor path is empty")
                return

        # get_node_or_null is a Node method, not a SceneTree method.
        # Pass the NodePath as-is — Godot evaluates relative paths relative to
        # the node the method is called on (cutscene_player here), and absolute
        # paths (starting with /) from the scene root.
        var actor_node: Node = cutscene_player.get_node_or_null(actor)

        if actor_node == null:
                push_warning("CutsceneActionAnimate: actor node not found at path '%s'" % actor)
                return

        # Find the AnimatedSprite3D — either the actor itself, or a child of it.
        var sprite: AnimatedSprite3D = null
        if actor_node is AnimatedSprite3D:
                sprite = actor_node as AnimatedSprite3D
        else:
                # Try to find a child AnimatedSprite3D.
                # We use find_child with recursive=true to search descendants.
                sprite = actor_node.find_child("Sprite", true, false) as AnimatedSprite3D
                if sprite == null:
                        # Fallback: search for any AnimatedSprite3D child
                        for child in actor_node.find_children("*", "AnimatedSprite3D", true, false):
                                sprite = child as AnimatedSprite3D
                                break

        if sprite == null:
                push_warning("CutsceneActionAnimate: no AnimatedSprite3D found on actor '%s'" % actor)
                return

        # Play the animation.
        # Note: If the animation doesn't exist in the SpriteFrames, this will
        # print an error to the Output panel but won't crash.
        sprite.play(animation)

        # Optionally wait for the animation to finish.
        # `animation_finished` is emitted when a NON-LOOPING animation completes.
        # For looping animations, this signal never fires — that's why we have
        # the wait_for_completion option.
        if wait_for_completion:
                # Connect one-shot and await
                # We use a local variable to capture the signal connection so we
                # can disconnect after it fires (avoiding signal accumulation).
                await sprite.animation_finished


func skip(_cutscene_player: Node) -> void:
        # Nothing to clean up — the animation continues playing in the background.
        # If wait_for_completion is true, the await will resolve when the
        # animation finishes (or never, for looping animations — but the
        # cutscene player stops awaiting, so it doesn't matter).
        pass
