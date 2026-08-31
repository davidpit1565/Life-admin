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
        // Reloading only the new markedDays leaves a stale dot on any day that WAS marked but no
        // longer is (its last item got deleted or completed) — UICalendarView only re-queries the
        // delegate for the days it's told to reload, so a day nobody asks about keeps showing
        // whatever it last rendered. Reload the union of old and new so a removed day gets a
        // chance to clear its decoration too, not just newly-added ones to gain one.
        let daysToReload = context.coordinator.markedDays.union(markedDays)
        context.coordinator.markedDays = markedDays
        uiView.reloadDecorations(forDateComponents: Array(daysToReload), animated: false)

        // Keeps the visibly-displayed month in sync with `selectedDate` for any change that
        // didn't come from tapping a day in this same grid — most notably CalendarView's "Today"
        // button, which otherwise had no way to actually scroll the calendar back to the current
        // month: updating the @Binding alone doesn't move UICalendarView's own displayed page.
        // Guarded by `lastSyncedDate` so an unrelated re-render (e.g. markedDays changing after
        // an item is added elsewhere) doesn't re-trigger the scroll animation for no reason.
        let components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        if context.coordinator.lastSyncedDate != components {
            context.coordinator.lastSyncedDate = components
            uiView.setVisibleDateComponents(components, animated: true)
            (uiView.selectionBehavior as? UICalendarSelectionSingleDate)?.setSelected(components, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedDate: $selectedDate, markedDays: markedDays)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var selectedDate: Binding<Date>
        var markedDays: Set<DateComponents>
        var lastSyncedDate: DateComponents?

        init(selectedDate: Binding<Date>, markedDays: Set<DateComponents>) {
            self.selectedDate = selectedDate
            self.markedDays = markedDays
            self.lastSyncedDate = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate.wrappedValue)
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
            // Normalized to the same year/month/day-only shape updateUIView compares against —
            // recording it here avoids that redundantly re-issuing the exact same
            // setVisibleDateComponents/setSelected calls right back at the grid on the next render.
            lastSyncedDate = Calendar.current.dateComponents([.year, .month, .day], from: date)
            selectedDate.wrappedValue = date
        }
    }
}
