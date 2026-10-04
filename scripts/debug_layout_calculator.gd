@tool
extends EditorScript

## Run this script in Godot Editor (File -> Run, or Ctrl+Shift+X in the Script tab)
## to automatically calculate the exact launch flags for your current monitor layout!

func _run():
	print("==================================================================")
	print("          MULTI-INSTANCE DEBUG LAUNCH FLAGS CALCULATOR            ")
	print("==================================================================")
	
	var current_screen = DisplayServer.window_get_current_screen()
	var screen_rect = DisplayServer.screen_get_usable_rect(current_screen)
	var is_landscape = screen_rect.size.x >= screen_rect.size.y
	
	print("Active Screen: ", current_screen, " (", "Landscape" if is_landscape else "Portrait", ")")
	print("Usable Rect: ", screen_rect)
	
	var base_aspect = 16.0 / 9.0
	var spacing = 16
	var margin = 24
	var title_bar = 32
	
	for n in [2, 3, 4]:
		var cols = 1
		var rows = 1
		if n == 2:
			if is_landscape:
				var avail_w_for_2 = (float(screen_rect.size.x) - 2.0 * margin - spacing) / 2.0
				if avail_w_for_2 >= 480.0:
					cols = 2
					rows = 1
				else:
					cols = 1
					rows = 2
			else:
				cols = 1
				rows = 2
		elif n == 3:
			var avail_w_for_3 = (float(screen_rect.size.x) - 2.0 * margin - 2.0 * spacing) / 3.0
			if is_landscape and avail_w_for_3 >= 480.0:
				cols = 3
				rows = 1
			elif is_landscape:
				cols = 2
				rows = 2
			else:
				cols = 1
				rows = 3
		else:
			if is_landscape:
				cols = 2
				rows = 2
			else:
				cols = 2
				rows = 2
				
		var max_w = float(screen_rect.size.x - 2 * margin - (cols - 1) * spacing) / float(cols)
		var max_h = float(screen_rect.size.y - 2 * margin - (rows - 1) * (spacing + title_bar) - title_bar) / float(rows)
		
		var w = max_w
		var h = w / base_aspect
		if h > max_h:
			h = max_h
			w = h * base_aspect
			
		if not is_landscape and n == 2:
			var max_h_for_top = (float(screen_rect.size.y) / 2.0 - (spacing + title_bar) - margin) / 1.5
			if h > max_h_for_top:
				h = max_h_for_top
				w = h * base_aspect
			w *= 0.75
			h *= 0.75
		elif is_landscape and n <= 2:
			w = minf(w, 1152.0)
			h = w / base_aspect
			
		var win_size = Vector2i(int(w), int(h))
		
		print("\n--- FOR ", n, " INSTANCES (Window Size: ", win_size.x, "x", win_size.y, ") ---")
		if not is_landscape and n == 2:
			var pos_x = screen_rect.position.x + (screen_rect.size.x - win_size.x) / 2
			var top_y = screen_rect.position.y + 16
			var bottom_y = top_y + win_size.y + (spacing + title_bar)
			print("Instance 1 (Top) Launch Arg: --position ", pos_x, ",", top_y, " --resolution ", win_size.x, "x", win_size.y)
			print("Instance 2 (Bottom) Launch Arg: --position ", pos_x, ",", bottom_y, " --resolution ", win_size.x, "x", win_size.y)
		else:
			var total_w = cols * win_size.x + (cols - 1) * spacing
			var total_h = rows * win_size.y + (rows - 1) * (spacing + title_bar)
			
			var start_x = screen_rect.position.x + (screen_rect.size.x - total_w) / 2
			var start_y = screen_rect.position.y + (screen_rect.size.y - total_h) / 2
			start_y = maxi(start_y, screen_rect.position.y)
			for i in range(n):
				var col = i % cols
				var row = i / cols
				var x = start_x + col * (win_size.x + spacing)
				var y = start_y + row * (win_size.y + spacing + title_bar)
				print("Instance ", i + 1, " Launch Arg: --position ", x, ",", y, " --resolution ", win_size.x, "x", win_size.y)
			
	print("==================================================================")
