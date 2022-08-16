import {expect} from '../../../../util/reconfiguredChai';
import sinon from 'sinon';
import commonI18n from '@cdo/locale';
import {localizeWidgetLevel} from '@cdo/apps/sites/studio/pages/levels/_widget';

describe('localizeWidgetLevel', () => {
  it('localizes data-widget-i18n marked content', () => {
    // Stub the localize
    sinon.stub(commonI18n, 'activity').returns('localized');

    // Prepare a document that will be localized
    let el = document.createElement('span');
    el.textContent = 'original';
    el.setAttribute('data-widget-i18n', 'activity');
    document.body.appendChild(el);

    // Ensure it is localized
    localizeWidgetLevel();
    expect(el.textContent).to.equal('localized');
  });
});
