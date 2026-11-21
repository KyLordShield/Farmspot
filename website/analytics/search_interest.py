"""Explainable Crop Insights scoring for deduplicated user/crop observations."""

import json
import sys

MIN_SEARCHES = 30  # A period needs enough activity to be useful.
MIN_USERS = 5  # One or two users should never earn a crop a prediction.
MIN_DELTA = 1e-6


def score(history, previous, recent, current):
    """Return labeled crops ranked by current search proportion, change, and name."""

    def eligible(period):
        return min(period.get("total", 0), period.get("pairs", sum(crop_counts(period).values()))) >= MIN_SEARCHES

    def count(period, crop):
        return crop_counts(period).get(crop, 0)

    def share(period, crop):
        pairs = period.get("pairs", sum(crop_counts(period).values()))
        return count(period, crop) / pairs if pairs else 0.0

    results = []
    for crop in set(crop_counts(recent)) | set(crop_counts(current)) | {
        crop for period in history.values() for crop in crop_counts(period)
    }:
        users = count(recent, crop)
        months = [
            month for month, period in history.items()
            if eligible(period) and count(period, crop) >= MIN_USERS
        ]
        seasonal = sum(share(history[month], crop) for month in months) / len(months) if months else 0.0
        recent_share = share(recent, crop)
        current_share = share(current, crop)
        trend = recent_share - share(previous, crop)
        rising = eligible(previous) and trend > MIN_DELTA
        confirmed = current_share >= seasonal
        label, confidence = "Not enough data", None
        reason = "There is not enough supporting search activity to make an estimate."
        based_on = []
        if eligible(recent) and eligible(current) and min(users, count(current, crop)) >= MIN_USERS:
            if len(months) >= 2 and confirmed:
                label, confidence = "Seasonal prediction", "High"
                reason = "It drew interest in this month in several past years, and searches are holding up this month."
                based_on = [*months, "last 30 days", "this month so far"]
            elif len(months) == 1 and rising:
                label, confidence = "Likely seasonal", "Medium"
                reason = "People searched for it in this month in a prior year, and interest has risen recently."
                based_on = [*months, "last 30 days", "previous 30 days", "this month so far"]
            elif not months and rising:
                label, confidence = "Trending now", "Low"
                reason = "People have been searching for it more than usual recently."
                based_on = ["last 30 days", "previous 30 days", "this month so far"]
        results.append(dict(
            crop=crop, label=label, confidence=confidence,
            scores=dict(seasonal=seasonal, recent=recent_share, current=current_share, trend=trend),
            reason=reason, based_on=based_on, searchers=users,
        ))

    results.sort(key=lambda row: (-row["scores"]["current"], -row["scores"]["trend"], row["crop"].casefold()))
    return results


def crop_counts(period):
    # PHP serializes an empty associative array as [].
    return period.get("crops") or {}



def forecast(history):
    """Rank crops by average search share across completed matching months.

    Require two years with five independent searchers for the crop.
    Include zero shares from other sufficiently busy years in the average.
    """
    periods = {
        month: period for month, period in history.items()
        if period["pairs"] >= MIN_SEARCHES
    }
    crops = {crop for period in periods.values() for crop in crop_counts(period)}
    results = []
    for crop in crops:
        counts = [crop_counts(period).get(crop, 0) for period in periods.values()]
        if sum(count >= MIN_USERS for count in counts) >= 2:
            shares = [count / period["pairs"] for count, period in zip(counts, periods.values())]
            results.append({"crop": crop, "average_share": sum(shares) / len(shares)})
    results.sort(key=lambda row: (-row["average_share"], row["crop"].casefold(), row["crop"]))
    return {"based_on": list(periods), "crops": results[:3]}


if __name__ == "__main__":
    data = json.loads(sys.stdin.buffer.read())
    future_months = data.pop("future_months", [])
    forecasts = []
    for month in future_months:
        history = month.pop("history")
        forecasts.append({**month, **forecast(history)})
    json.dump({"predictions": score(**data), "forecast": forecasts}, sys.stdout, allow_nan=False)
