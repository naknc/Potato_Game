extends CanvasLayer
class_name UI

@onready var score_label = %Label
@onready var completed_ui = %GameCompleteUI

var score = 0
var maxScore = 3

func update_score(value):
	score += value
	update_score_label()
	
	if score >= maxScore:
		completed_ui.visible = true
		score_label.visible = false
	
func update_score_label():
	score_label.text = "Apple = " + str(score)
	

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

func _on_button_pressed():
	get_tree().reload_current_scene()
