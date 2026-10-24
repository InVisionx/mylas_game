extends Node
## Global signal bus.
##
## Systems never hold direct references to each other for one-off notifications.
## Anything that several unrelated systems care about is announced here.

# --- Shift / run flow -------------------------------------------------------
signal shift_started(shift_index: int, shift_data: Dictionary)
signal shift_ended(report: Dictionary)
signal shift_failed(reason: String)
signal customer_count_changed(served: int, total: int)
signal money_changed(amount: int, delta: int)

# --- Customers --------------------------------------------------------------
signal customer_entered(customer_id: int)
signal customer_reached_counter(customer_id: int)
signal customer_left(customer_id: int)
signal customer_became_active(customer_id: int)
signal queue_changed(length: int)
signal dialogue_line(speaker: String, text: String)
signal customer_state_changed(customer_id: int, state: String)

# --- Checkout ---------------------------------------------------------------
signal item_placed_on_belt(item: Node)
signal item_scanned(item: Node, price: int)
signal scan_failed(reason: String)
signal checkout_ready()
signal checkout_completed()
signal register_anomaly(id: String, data: Dictionary)
signal receipt_printed(text: String)

# --- Decisions --------------------------------------------------------------
signal decision_made(customer_id: int, approved: bool)
signal decision_resolved(customer_id: int, approved: bool, correct: bool, was_entity: bool)
signal entity_escaped(customer_id: int)
signal innocence_violated(customer_id: int)

# --- Inspection -------------------------------------------------------------
signal inspection_started(customer_id: int)
signal inspection_ended()
signal inspection_focus_changed(focus: String, label: String)
signal inspection_progress(ratio: float)
signal clue_found(clue_id: String, text: String)
signal clue_already_known(clue_id: String)

# --- Horror -----------------------------------------------------------------
signal horror_event_started(event_id: String)
signal horror_event_finished(event_id: String)
signal jumpscare_started(kind: String)
signal jumpscare_finished(kind: String)
signal atmosphere(stage: int)

# --- UI / meta --------------------------------------------------------------
signal notify(text: String, tone: String)
signal request_pause(paused: bool)
signal ui_sound(name: String)
signal graphics_changed()
signal settings_changed()
signal notebook_updated()
signal save_completed()
