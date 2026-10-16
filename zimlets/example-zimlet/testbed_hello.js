/*
 * Example zimlet handler for the Zimbra 9 SAML testbed.
 */
function com_zimbra_testbed_hello_HandlerObject() {
}

com_zimbra_testbed_hello_HandlerObject.prototype = new ZmZimletBase();
com_zimbra_testbed_hello_HandlerObject.prototype.constructor = com_zimbra_testbed_hello_HandlerObject;

var TestbedZimlet = com_zimbra_testbed_hello_HandlerObject;

TestbedZimlet.prototype.singleClicked = function () {
    ZmDialog.showAlert(this.getMessage("TestbedZimlet_alert_title"),
        this.getMessage("TestbedZimlet_alert_message"));
};

TestbedZimlet.prototype.doubleClicked = function () {
    this.singleClicked();
};
