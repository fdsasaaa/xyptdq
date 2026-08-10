<br>会员的id号：{$value}
<br>会员头像：{dr_avatar($value)}<br><br>

如果调用会员其他字段，必须先调用这句话：<br>{php $user=dr_member_info($value);}
<br>
<br>会员name：{$user.name}
<br>会员username：{$user.username}
<br>会员phone：{$user.phone}
<br>会员email：{$user.email}
<a href="javascript:top.dr_iframe_show('会员自定义字段', '{SELF}?s=mbdy&c=member&m=index&return=user', '90%');">点击生成其他会员自定义字段</a>