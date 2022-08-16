/**
 * @file JavaScript loaded in all Widget-type levels.
 */
/* global appOptions */
import $ from 'jquery';
import React from 'react';
import {
  showDialog,
  processResults
} from '@cdo/apps/code-studio/levels/dialogHelper';
import {registerGetResult} from '@cdo/apps/code-studio/levels/codeStudioLevels';
import {setupApp} from '@cdo/apps/code-studio/initApp/loadApp';
import {
  LegacyStartOverDialog,
  LegacyInstructionsDialog
} from '@cdo/apps/lib/ui/LegacyDialogContents';
import i18n from '@cdo/locale';

export function showInstructionsDialog() {
  showDialog(
    <LegacyInstructionsDialog
      title={i18n.puzzleTitle({
        stage_total: appOptions.level.lesson_total,
        puzzle_number: appOptions.level.puzzle_number
      })}
      markdown={appOptions.level.longInstructions}
    />
  );
  $('details').details();
}

function setupWidgetLevel() {
  window.script_path = location.pathname;
  setupApp(appOptions);

  appOptions.showInstructionsWrapper(showInstructionsDialog);
  registerGetResult();
  window.options = appOptions.level;
}

// Find and replaces content with `data-widget-i18n` attributes with the given
// localization strings.
export function localizeWidgetLevel() {
  // Since some widgets are 'html' content, they have to be patched to perform
  // localization. (Used for at least the Pixelation widget.)
  $('[data-widget-i18n]').each(function(el) {
    // Get a localization key from the 'data-widget-i18n' attribute.
    let key = $(this).data('widget-i18n');

    // Set the text of the element to the localized string.
    if (i18n[key]) {
      $(this).text(i18n[key]());
    }
  });

  // Do the same thing but for the title text.
  $('[data-widget-title-i18n]').each(function(el) {
    // Get a localization key from the 'data-widget-title-i18n' attribute.
    let key = $(this).data('widget-title-i18n');

    // Set the text of the element's title attribute to the localized string.
    if (i18n[key]) {
      $(this).prop('title', i18n[key]());
    }
  });
}

// Add globals
window.CodeMirror = require('codemirror');
window.dashboard = window.dashboard || {};
window.dashboard.widget = {
  setupWidgetLevel: setupWidgetLevel,
  // used by pixelation widget
  showStartOverDialog: callback =>
    showDialog(<LegacyStartOverDialog />, callback),
  // used by frequency, vigenere, and pixelation widgets
  processResults: processResults
};

// On load (note - widget-specific setup may happen before this!)
$(document).ready(function() {
  $('#bubble').click(showInstructionsDialog);

  // Localize any strings embedded in the widget.
  localizeWidgetLevel();
});
