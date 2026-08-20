import SwiftUI
import UIKit

struct CalendarGridView: UIViewRepresentable {
    @Binding var selectedDate: Date
    let markedDays: Set<DateComponents>

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Calendar.current
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.selectedDate = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        view.selectionBehavior = selection
        return view
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.markedDays = markedDays
        uiView.reloadDecorations(forDateComponents: Array(markedDays), animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedDate: $selectedDate, markedDays: markedDays)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var selectedDate: Binding<Date>
        var markedDays: Set<DateComponents>

        init(selectedDate: Binding<Date>, markedDays: Set<DateComponents>) {
            self.selectedDate = selectedDate
            self.markedDays = markedDays
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let year = dateComponents.year, let month = dateComponents.month, let day = dateComponents.day else { return nil }
            var normalized = DateComponents()
            normalized.year = year
            normalized.month = month
            normalized.day = day
            guard markedDays.contains(normalized) else { return nil }
            return .default(color: .systemIndigo, size: .small)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let date = Calendar.current.date(from: dateComponents) else { return }
            selectedDate.wrappedValue = date
        }
    }
}
