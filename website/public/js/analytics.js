const cropChart = document.getElementById('cropChart');
const growthChart = document.getElementById('growthChart');
const cropLabels = JSON.parse(cropChart.dataset.labels);
const cropValues = JSON.parse(cropChart.dataset.values);
const growthLabels = JSON.parse(growthChart.dataset.labels);
const growthValues = JSON.parse(growthChart.dataset.values);

new Chart(cropChart, {
    type: 'bar',
    data: {
        labels: cropLabels,
        datasets: [{
            data: cropValues,
            backgroundColor: ['#1b6b2c', '#3d9347', '#6fcf6f', '#a9d8b4', '#c8e6d0', '#e2efe6'],
            borderRadius: 6
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: { display: false }
        },
        scales: {
            x: {
                grid: { display: false }
            },
            y: {
                beginAtZero: true,
                ticks: { precision: 0 },
                grid: { color: '#eef1f0' }
            }
        }
    }
});

new Chart(growthChart, {
    type: 'bar',
    data: {
        labels: growthLabels,
        datasets: [{
            data: growthValues,
            backgroundColor: ['#e2efe6', '#c8e6d0', '#6fcf6f', '#1b6b2c'],
            borderRadius: 6
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: { display: false }
        },
        scales: {
            x: {
                grid: { display: false }
            },
            y: {
                beginAtZero: true,
                ticks: { precision: 0 },
                grid: { color: '#eef1f0' }
            }
        }
    }
});
