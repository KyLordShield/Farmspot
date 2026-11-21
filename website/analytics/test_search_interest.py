import unittest

from search_interest import score


def period(**crops):
    return {"total": sum(crops.values()), "crops": crops}


class SearchInterestTests(unittest.TestCase):
    def test_confidence_levels_and_stale_history(self):
        old = period(tomato=12, squash=8, other=80)
        history = {"Nov 2023": old, "Nov 2024": old, "Nov 2025": period(
            tomato=12, squash=8, lettuce=9, other=71)}
        past = period(tomato=8, ginger=2, lettuce=2, other=88)
        recent = period(tomato=20, ginger=15, lettuce=15, radish=1, other=49)
        results = {item["crop"]: item for item in score(history, past, recent, recent)}
        self.assertEqual(results["tomato"]["confidence"], "High")
        self.assertEqual(results["lettuce"]["confidence"], "Medium")
        self.assertEqual(results["ginger"]["confidence"], "Low")
        for crop in ("squash", "radish"):
            self.assertEqual(results[crop]["label"], "Not enough data")

    def test_uses_proportions_and_preserves_ties(self):
        past = period(crop=15, other=185)
        recent = period(crop=12, other=88)
        rows = {row["crop"]: row for row in score({}, past, recent, recent)}
        self.assertEqual(rows["crop"]["label"], "Trending now")
        rows = {row["crop"]: row for row in score({}, recent, past, past)}
        self.assertIsNone(rows["crop"]["confidence"])
        tied = period(d=12, c=12, b=12, a=12)
        self.assertEqual([row["crop"] for row in score({}, tied, tied, tied)], list("abcd"))

    def test_empty_small_and_partial_periods(self):
        self.assertEqual(score({}, {}, {}, {}), [])
        self.assertIsNone(score({}, {}, period(crop=1), period(crop=1))[0]["confidence"])
        recent = period(crop=20, other=30)
        current = period(crop=5, other=4)
        self.assertIsNone(score({}, period(crop=5, other=45), recent, current)[0]["confidence"])

    def test_repeated_searches_do_not_change_proportion(self):
        recent = dict(total=130, pairs=31, crops={"crop": 1, "other": 30})
        row = next(row for row in score({}, {}, recent, recent) if row["crop"] == "crop")
        self.assertAlmostEqual(row["scores"]["recent"], 1 / 31)
        self.assertIsNone(row["confidence"])



class ForecastTest(unittest.TestCase):
    def test_requires_two_busy_years_and_ranks_by_share(self):
        from search_interest import forecast

        result = forecast({
            "Dec 2023": {"pairs": 0, "crops": []},
            "Dec 2024": {"pairs": 40, "crops": {"tomato": 20, "corn": 5}},
            "Dec 2025": {"pairs": 200, "crops": {"tomato": 20, "corn": 40, "ginger": 30}},
        })
        self.assertEqual(result["based_on"], ["Dec 2024", "Dec 2025"])
        self.assertEqual([row["crop"] for row in result["crops"]], ["tomato", "corn"])
        self.assertAlmostEqual(result["crops"][0]["average_share"], 0.3)

    def test_empty_and_small_periods_do_not_make_forecasts(self):
        from search_interest import forecast

        self.assertEqual(forecast({})["crops"], [])
        self.assertEqual(forecast({
            "Jan 2024": {"pairs": 29, "crops": {"tomato": 20}},
            "Jan 2025": {"pairs": 90, "crops": {"tomato": 10}},
        })["crops"], [])

if __name__ == "__main__":
    unittest.main()
