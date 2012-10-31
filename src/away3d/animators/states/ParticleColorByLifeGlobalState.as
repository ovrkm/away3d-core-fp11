package away3d.animators.states
{
	import away3d.animators.data.ParticleRenderParameter;
	import away3d.animators.nodes.ParticleColorByLifeGlobalNode;
	import away3d.animators.nodes.ParticleNodeBase;
	import away3d.animators.ParticleAnimator;
	/**
	 * ...
	 * @author ...
	 */
	public class ParticleColorByLifeGlobalState extends ParticleStateBase
	{
		private var colorNode:ParticleColorByLifeGlobalNode;
		
		public function ParticleColorByLifeGlobalState(animator:ParticleAnimator, particleNode:ParticleNodeBase)
		{
			super(animator, particleNode);
			this.colorNode = particleNode as ParticleColorByLifeGlobalNode;
			
		}
		
		override public function setRenderState(parameter:ParticleRenderParameter) : void
		{
			if (parameter.animationRegisterCache.hasColorNode && parameter.animationRegisterCache.needFragmentAnimation)
			{
				var index:int;
				var data:Vector.<Number>;
				if (colorNode.needMultiple)
				{
					index = parameter.animationRegisterCache.getRegisterIndex(particleNode, ParticleColorByLifeGlobalNode.START_MULTIPLIER_CONSTANT_REGISTER);
					data = colorNode.startMultiplierData;
					parameter.animationRegisterCache.setFragmentConst(index, data[0], data[1], data[2], data[3]);
					index = parameter.animationRegisterCache.getRegisterIndex(particleNode, ParticleColorByLifeGlobalNode.DELTA_MULTIPLIER_CONSTANT_REGISTER);
					data = colorNode.deltaMultiplierData;
					parameter.animationRegisterCache.setFragmentConst(index, data[0], data[1], data[2], data[3]);
				}
				if (colorNode.needOffset)
				{
					index = parameter.animationRegisterCache.getRegisterIndex(particleNode, ParticleColorByLifeGlobalNode.START_OFFSET_CONSTANT_REGISTER);
					data = colorNode.startOffsetData;
					parameter.animationRegisterCache.setFragmentConst(index, data[0], data[1], data[2], data[3]);
					index = parameter.animationRegisterCache.getRegisterIndex(particleNode, ParticleColorByLifeGlobalNode.DELTA_OFFSET_CONSTANT_REGISTER);
					data = colorNode.deltaOffsetData;
					parameter.animationRegisterCache.setFragmentConst(index, data[0], data[1], data[2], data[3]);
				}
			}
		}
		
	}

}