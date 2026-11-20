const range = document.getElementById('analytics-range');
const custom = document.getElementById('analytics-custom');

function syncRange() {
    custom.hidden = range.value !== 'custom';
    custom.disabled = custom.hidden;
    custom.querySelectorAll('input').forEach(input => { input.required = !custom.hidden; });
}

range.addEventListener('change', syncRange);
syncRange();

const updated = document.getElementById('analytics-updated');
const age = document.getElementById('analytics-age');
const relative = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });

function showAge() {
    const minutes = Math.max(0, Math.floor((Date.now() - Date.parse(updated.dateTime)) / 60000));
    age.textContent = minutes === 0 ? ' · just now'
        : ' · ' + (minutes < 60 ? relative.format(-minutes, 'minute')
            : minutes < 1440 ? relative.format(-Math.floor(minutes / 60), 'hour')
                : relative.format(-Math.floor(minutes / 1440), 'day'));
}
showAge();
setInterval(showAge, 60000);

const green = '#15803d';
const muted = '#4b5563';
const formatCount = new Intl.NumberFormat('en-PH');
const valueLabels = {
    id: 'analyticsValueLabels',
    afterDatasetsDraw(chart) {
        const horizontal = chart.options.indexAxis === 'y';
        const { ctx } = chart;
        ctx.save();
        ctx.fillStyle = '#111827';
        ctx.font = '600 12px system-ui';
        ctx.textAlign = horizontal ? 'left' : 'center';
        ctx.textBaseline = horizontal ? 'middle' : 'bottom';
        chart.getDatasetMeta(0).data.forEach(({ x, y }, index) => {
            ctx.fillText(formatCount.format(chart.data.datasets[0].data[index]), x + (horizontal ? 7 : 0), y - (horizontal ? 0 : 5));
        });
        ctx.restore();
    }
};

function renderChart(canvas, horizontal) {
    if (!canvas || typeof Chart === 'undefined') return;

    const area = canvas.closest('[data-chart-area]');
    const labels = JSON.parse(canvas.dataset.labels);
    const values = JSON.parse(canvas.dataset.values);
    const fullLabels = labels.map((label, index) => !horizontal && index === labels.length - 1 ? label + ' · so far' : label);
    const numberAxis = {
        beginAtZero: true,
        grace: '12%',
        ticks: { color: muted, precision: 0, callback: value => Number.isInteger(value) ? formatCount.format(value) : '' },
        grid: { color: '#e5e7eb' },
        border: { display: false }
    };
    const categoryAxis = {
        ticks: {
            color: muted, font: { size: horizontal ? 14 : 12 },
            callback(value) {
                const label = fullLabels[value];
                return horizontal && label.length > 24 ? label.slice(0, 23) + '…' : label;
            }
        },
        grid: { display: false },
        border: { display: false }
    };

    area.hidden = false;
    requestAnimationFrame(() => {
        try {
            new Chart(canvas, {
                type: 'bar',
                data: {
                    labels: fullLabels,
                    datasets: [{
                        data: values,
                        backgroundColor: values.map((_, index) => !horizontal && index === values.length - 1 ? '#16a34a' : green),
                        borderRadius: 7,
                        maxBarThickness: horizontal ? 24 : 44
                    }]
                },
                options: {
                    indexAxis: horizontal ? 'y' : 'x',
                    responsive: true,
                    maintainAspectRatio: false,
                    animation: false,
                    layout: { padding: horizontal ? { right: 54 } : { top: 16 } },
                    scales: { x: horizontal ? numberAxis : categoryAxis, y: horizontal ? categoryAxis : numberAxis },
                    plugins: {
                        legend: { display: false },
                        tooltip: { callbacks: { label: context => formatCount.format(context.raw) } }
                    }
                },
                plugins: [valueLabels]
            });
            area.querySelector('.analytics-skeleton').hidden = true;
            area.nextElementSibling.open = false;
        } catch (error) {
            area.hidden = true;
            console.error('Analytics chart could not be drawn', error);
        }
    });
}

renderChart(document.getElementById('cropChart'), true);
renderChart(document.getElementById('growthChart'), false);
