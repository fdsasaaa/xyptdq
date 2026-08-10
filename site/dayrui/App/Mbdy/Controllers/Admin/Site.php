<?php namespace Phpcmf\Controllers\Admin;

class Site extends \Phpcmf\App
{

    private function get_field() {
        return \Phpcmf\Service::M('field')->get_mysite_field(SITE_ID);
    }

    public function index() {

        if (version_compare(CMF_VERSION, '4.5.2') < 0) {
            $this->_admin_msg(0, '本功能需要cms版本在4.5.2以上才能使用，当前版本v'.CMF_VERSION);
        }

        $field = $this->get_field();
        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '网站信息字段的模板调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'field' => $field,
            'return' => dr_safe_filename($_GET['return']),
        ]);
        \Phpcmf\Service::V()->display('site.html');
    }

    public function cms() {

        $field = $this->get_field();
        \Phpcmf\Service::V()->assign([
            'code' => '{SITE_NAME} 当前网站名称
{SITE_LOGO} 当前网站的logo图片
{SITE_ICP} 网站ICP备案号
{SITE_URL} 网站地址
{SITE_TONGJI} 网站统计代码',
            'field' => $field,
        ]);
        \Phpcmf\Service::V()->display('site_cms.html');
    }

    public function tag() {

        $html = '';
        $post = \Phpcmf\Service::L('input')->xss_clean($_POST);
        if (!$post) {
            $this->_json(1, '字段参数没过来');
        }
        $fid = dr_safe_filename($post['field']);
        if (!$fid) {
            $this->_json(1, '字段参数没过来');
        }

        $field = $this->get_field();

        $field = $field[$fid];
        if (!$field) {
            $this->_json(1, '字段['.$fid.']不存在');
        }


        $html = \Phpcmf\Service::M('code', APP_DIR)->get_site_field_code($field);

        $this->_json(1, $html);

    }

}
