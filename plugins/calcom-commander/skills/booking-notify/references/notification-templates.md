# Notification Templates

Telegram message templates for booking notifications.

## New Booking

```html
<b>New Booking</b> <b>Event:</b> {{eventTitle}}
<b>Attendee:</b> {{attendeeName}} ({{attendeeEmail}}) <b>When:</b> {{startTime}}
- {{endTime}} <b>Timezone:</b> {{timezone}} {{#if notes}}<b>Notes:</b>
{{notes}}{{/if}}
```

## Cancellation

```html
<b>Booking Cancelled</b> <b>Event:</b> {{eventTitle}}
<b>Attendee:</b> {{attendeeName}} <b>Was scheduled:</b> {{startTime}} {{#if
cancellationReason}}<b>Reason:</b> {{cancellationReason}}{{/if}}
```

## Upcoming Reminder

```html
<b>Upcoming in {{minutesUntil}} min</b> <b>Event:</b> {{eventTitle}}
<b>With:</b> {{attendeeName}} <b>Time:</b> {{startTime}} - {{endTime}}
```

## Rescheduled

```html
<b>Booking Rescheduled</b> <b>Event:</b> {{eventTitle}}
<b>Attendee:</b> {{attendeeName}} <b>Old time:</b> <s>{{oldStartTime}}</s>
<b>New time:</b> {{newStartTime}} - {{newEndTime}}
```

## Daily Summary

```html
<b>Today's Bookings ({{count}})</b> {{#each bookings}} {{time}} — {{title}} with
{{attendee}} {{/each}}
```

## Emoji Map

| Category     | Emoji |
| ------------ | ----- |
| NEW BOOKING  | 📅    |
| CANCELLATION | ❌    |
| UPCOMING     | ⏰    |
| RESCHEDULED  | 🔄    |
| DAILY        | 📋    |
