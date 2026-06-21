import SwiftUI
import UIKit

/// Wraps UIDatePicker in .countDownTimer mode to provide a native hours/minutes
/// wheel picker for duration input.
struct DurationPicker: UIViewRepresentable {
    @Binding var duration: TimeInterval

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .countDownTimer
        picker.countDownDuration = duration
        picker.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        // Only push updates in from outside if the value actually changed,
        // to avoid fighting the picker's own interaction.
        if abs(uiView.countDownDuration - duration) > 1 {
            uiView.countDownDuration = duration
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(duration: $duration)
    }

    final class Coordinator: NSObject {
        private let duration: Binding<TimeInterval>

        init(duration: Binding<TimeInterval>) {
            self.duration = duration
        }

        @objc func valueChanged(_ picker: UIDatePicker) {
            duration.wrappedValue = picker.countDownDuration
        }
    }
}
