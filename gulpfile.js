/**
 * gulpfile.js — Pipeline de assets para claudeMerge
 *
 * Tareas disponibles:
 *   gulp          → build completo + watch
 *   gulp build    → compila y minifica CSS y JS una vez
 *   gulp watch    → observa cambios y recompila automáticamente
 *   gulp styles   → solo compila SCSS → CSS minificado
 *   gulp scripts  → solo minifica JS
 *   gulp clean    → borra la carpeta dist/
 *
 * Salida:
 *   static/dist/css/main.min.css
 *   static/dist/js/main.min.js
 */

'use strict';

const gulp        = require('gulp');
const sass        = require('gulp-sass')(require('sass'));
const cleanCSS    = require('gulp-clean-css');
const uglify      = require('gulp-uglify');
const rename      = require('gulp-rename');
const sourcemaps  = require('gulp-sourcemaps');
const concat      = require('gulp-concat');
const { deleteAsync } = require('del');

// ── Rutas ────────────────────────────────────────────────────────────────────

const paths = {
  styles: {
    src:  'static/scss/**/*.scss',
    main: 'static/scss/main.scss',
    dest: 'static/dist/css',
  },
  scripts: {
    src:  'static/js/**/*.js',
    dest: 'static/dist/js',
  },
};

// ── Limpieza ─────────────────────────────────────────────────────────────────

function clean() {
  return deleteAsync(['static/dist']);
}

// ── Estilos ──────────────────────────────────────────────────────────────────

function styles() {
  return gulp
    .src(paths.styles.main)
    .pipe(sourcemaps.init())
    .pipe(
      sass({ outputStyle: 'expanded' }).on('error', sass.logError)
    )
    .pipe(rename('main.css'))
    .pipe(gulp.dest(paths.styles.dest))       // CSS sin minificar (para dev)
    .pipe(cleanCSS({ level: 2 }))
    .pipe(rename({ suffix: '.min' }))
    .pipe(sourcemaps.write('.'))
    .pipe(gulp.dest(paths.styles.dest));      // main.min.css + main.min.css.map
}

// ── Scripts ──────────────────────────────────────────────────────────────────

function scripts() {
  return gulp
    .src(paths.scripts.src)
    .pipe(sourcemaps.init())
    .pipe(concat('main.js'))
    .pipe(gulp.dest(paths.scripts.dest))      // JS sin minificar (para dev)
    .pipe(uglify())
    .pipe(rename({ suffix: '.min' }))
    .pipe(sourcemaps.write('.'))
    .pipe(gulp.dest(paths.scripts.dest));     // main.min.js + main.min.js.map
}

// ── Watch ────────────────────────────────────────────────────────────────────

function watch() {
  gulp.watch(paths.styles.src, styles);
  gulp.watch(paths.scripts.src, scripts);
}

// ── Tareas exportadas ────────────────────────────────────────────────────────

const build = gulp.series(clean, gulp.parallel(styles, scripts));

exports.clean   = clean;
exports.styles  = styles;
exports.scripts = scripts;
exports.watch   = watch;
exports.build   = build;
exports.default = gulp.series(build, watch);
