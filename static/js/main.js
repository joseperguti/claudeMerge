/**
 * main.js — Lógica principal del frontend
 */

(function () {
  'use strict';

  // --- Alertas con auto-cierre ---
  function initAlerts() {
    const alerts = document.querySelectorAll('.alert[data-auto-close]');
    alerts.forEach(function (alert) {
      const delay = parseInt(alert.dataset.autoClose, 10) || 4000;
      setTimeout(function () {
        alert.style.transition = 'opacity 0.4s ease';
        alert.style.opacity = '0';
        setTimeout(function () {
          alert.remove();
        }, 400);
      }, delay);
    });
  }

  // --- Confirmación de acciones destructivas ---
  function initConfirmButtons() {
    document.addEventListener('click', function (e) {
      const btn = e.target.closest('[data-confirm]');
      if (!btn) return;
      const message = btn.dataset.confirm || '¿Estás seguro?';
      if (!window.confirm(message)) {
        e.preventDefault();
      }
    });
  }

  // --- Toggle de visibilidad (ej. contraseña) ---
  function initToggleVisibility() {
    document.querySelectorAll('[data-toggle-target]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        const targetId = btn.dataset.toggleTarget;
        const target = document.getElementById(targetId);
        if (!target) return;
        const isHidden = target.style.display === 'none' || target.hidden;
        target.style.display = isHidden ? '' : 'none';
        target.hidden = !isHidden;
      });
    });
  }

  // --- Inicialización ---
  function init() {
    initAlerts();
    initConfirmButtons();
    initToggleVisibility();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
